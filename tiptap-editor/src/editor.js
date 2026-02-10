import { Editor, Extension, Mark } from '@tiptap/core';
import StarterKit from '@tiptap/starter-kit';
import TaskList from '@tiptap/extension-task-list';
import TaskItem from '@tiptap/extension-task-item';
import Table from '@tiptap/extension-table';
import TableRow from '@tiptap/extension-table-row';
import TableCell from '@tiptap/extension-table-cell';
import TableHeader from '@tiptap/extension-table-header';
import Image from '@tiptap/extension-image';
import Heading from '@tiptap/extension-heading';
import CodeBlockLowlight from '@tiptap/extension-code-block-lowlight';
import Placeholder from '@tiptap/extension-placeholder';
import Paragraph from '@tiptap/extension-paragraph';
import HardBreak from '@tiptap/extension-hard-break';
import { NodeSelection, Plugin, PluginKey, TextSelection } from '@tiptap/pm/state';
import { Decoration, DecorationSet } from '@tiptap/pm/view';
import { Markdown } from 'tiptap-markdown';
import { common, createLowlight } from 'lowlight';
import {
  createSlashCommands,
  handleNativeSlashClick,
  handleNativeSlashKey,
  isSlashPopupActive,
} from './slash-commands.js';
import { normalizeMarkdownForPersistence } from './markdown-normalization.mjs';

const lowlight = createLowlight(common);

const escapedHtmlTagPattern = /&lt;(?:\/)?(?:p|h[1-6]|ul|ol|li|table|thead|tbody|tr|td|th|blockquote|pre|code|img|hr)\b/i;
const htmlTagPattern = /<(?:\/)?(?:p|h[1-6]|ul|ol|li|table|thead|tbody|tr|td|th|blockquote|pre|code|img|hr)\b/i;
const fileProtocolPathPattern = /\(file:\/\/\/([^)]+)\)/g;
const IMAGE_RESIZE_MIN_WIDTH = 80;
const IMAGE_RESIZE_MAX_WIDTH = 2000;
const supportedTextAlignments = ['left', 'center', 'right'];

function postEditorDiagnostic(kind, message) {
  const handler = window.webkit?.messageHandlers?.editorError;
  if (!handler) return;

  handler.postMessage({
    kind,
    message: String(message ?? ''),
  });
}

window.addEventListener('error', (event) => {
  postEditorDiagnostic('error', event?.message ?? 'Unknown editor error');
});

window.addEventListener('unhandledrejection', (event) => {
  const reason = event?.reason;
  if (reason instanceof Error) {
    postEditorDiagnostic('rejection', reason.message);
    return;
  }
  postEditorDiagnostic('rejection', String(reason ?? 'Unhandled rejection'));
});

function parsePositiveInt(value) {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function escapeHtmlAttr(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

const CiderTextAlign = Extension.create({
  name: 'ciderTextAlign',

  addOptions() {
    return {
      types: ['paragraph', 'heading'],
      alignments: supportedTextAlignments,
    };
  },

  addGlobalAttributes() {
    return [
      {
        types: this.options.types,
        attributes: {
          textAlign: {
            default: null,
            parseHTML: (element) => {
              const value = element.style?.textAlign;
              return this.options.alignments.includes(value) ? value : null;
            },
            renderHTML: (attributes) => {
              if (!attributes.textAlign || attributes.textAlign === 'left') {
                return {};
              }

              return { style: `text-align: ${attributes.textAlign}` };
            },
          },
        },
      },
    ];
  },

  addCommands() {
    const applyAlignmentToSelection = (alignment, state, dispatch, types) => {
      const { selection } = state;
      const { from, to, $from } = selection;
      const normalizedAlignment = alignment === 'left' ? null : alignment;
      let tr = state.tr;
      let changed = false;

      state.doc.nodesBetween(from, to, (node, pos) => {
        if (!types.includes(node.type.name)) {
          return true;
        }

        if (node.attrs?.textAlign === normalizedAlignment) {
          return true;
        }

        tr = tr.setNodeMarkup(pos, undefined, {
          ...node.attrs,
          textAlign: normalizedAlignment,
        });
        changed = true;
        return true;
      });

      // Collapsed selections can miss their parent block in nodesBetween.
      if (!changed && selection.empty) {
        for (let depth = $from.depth; depth > 0; depth -= 1) {
          const node = $from.node(depth);
          if (!types.includes(node.type.name)) {
            continue;
          }

          if (node.attrs?.textAlign === normalizedAlignment) {
            break;
          }

          tr = tr.setNodeMarkup($from.before(depth), undefined, {
            ...node.attrs,
            textAlign: normalizedAlignment,
          });
          changed = true;
          break;
        }
      }

      if (!changed) {
        return false;
      }

      if (dispatch) {
        dispatch(tr);
      }

      return true;
    };

    return {
      setTextAlign: (alignment) => ({ state, dispatch }) => {
        if (!this.options.alignments.includes(alignment)) {
          return false;
        }

        return applyAlignmentToSelection(
          alignment,
          state,
          dispatch,
          this.options.types
        );
      },
      unsetTextAlign: () => ({ state, dispatch }) =>
        applyAlignmentToSelection(
          'left',
          state,
          dispatch,
          this.options.types
        ),
    };
  },
});

const CiderUnderline = Mark.create({
  name: 'underline',

  parseHTML() {
    return [
      { tag: 'u' },
      {
        style: 'text-decoration',
        getAttrs: value =>
          typeof value === 'string' && value.includes('underline') ? {} : false,
      },
    ];
  },

  renderHTML({ HTMLAttributes }) {
    return ['u', HTMLAttributes, 0];
  },

  addCommands() {
    return {
      setUnderline: () => ({ commands }) => commands.setMark(this.name),
      toggleUnderline: () => ({ commands }) => commands.toggleMark(this.name),
      unsetUnderline: () => ({ commands }) => commands.unsetMark(this.name),
    };
  },

  addKeyboardShortcuts() {
    return {
      'Mod-u': () => this.editor.commands.toggleUnderline(),
    };
  },
});

const CiderLink = Mark.create({
  name: 'link',
  inclusive: false,

  addAttributes() {
    return {
      href: {
        default: null,
      },
      target: {
        default: '_blank',
      },
      rel: {
        default: 'noopener noreferrer',
      },
    };
  },

  parseHTML() {
    return [
      {
        tag: 'a[href]',
        getAttrs: element => {
          const href = element.getAttribute('href');
          if (!href) return false;

          return {
            href,
            target: element.getAttribute('target') || '_blank',
            rel: element.getAttribute('rel') || 'noopener noreferrer',
          };
        },
      },
    ];
  },

  renderHTML({ HTMLAttributes }) {
    if (!HTMLAttributes.href) {
      return ['span', 0];
    }

    return ['a', HTMLAttributes, 0];
  },

  addCommands() {
    return {
      setLink: attributes => ({ commands }) => {
        if (!attributes?.href) return false;
        return commands.setMark(this.name, attributes);
      },
      toggleLink: attributes => ({ commands }) => {
        if (!attributes?.href) return false;
        return commands.toggleMark(this.name, attributes);
      },
      unsetLink: () => ({ commands }) => commands.unsetMark(this.name),
    };
  },
});

const CiderParagraph = Paragraph.extend({
  addStorage() {
    const parentStorage = this.parent?.() ?? {};

    return {
      ...parentStorage,
      markdown: {
        ...parentStorage.markdown,
        serialize(state, node, parent) {
          const parentTypeName = parent?.type?.name ?? '';
          const allowsInlineParagraphHTML = parentTypeName === 'doc';
          const textAlign = node.attrs?.textAlign;
          const hasCustomAlignment = allowsInlineParagraphHTML && textAlign && textAlign !== 'left';

          if (node.content.size === 0) {
            if (allowsInlineParagraphHTML && hasCustomAlignment) {
              state.write(`<p style="text-align: ${escapeHtmlAttr(textAlign)}"></p>`);
            } else if (allowsInlineParagraphHTML) {
              state.write('<p></p>');
            } else {
              state.renderInline(node);
            }
            state.closeBlock(node);
            return;
          }

          if (hasCustomAlignment) {
            state.write(`<p style="text-align: ${escapeHtmlAttr(textAlign)}">`);
            state.renderInline(node);
            state.write('</p>');
          } else {
            state.renderInline(node);
          }

          state.closeBlock(node);
        },
      },
    };
  },
});

const CiderHeading = Heading.extend({
  addStorage() {
    const parentStorage = this.parent?.() ?? {};

    return {
      ...parentStorage,
      markdown: {
        ...parentStorage.markdown,
        serialize(state, node, parent) {
          const parentTypeName = parent?.type?.name ?? '';
          const allowsInlineHeadingHTML = parentTypeName === 'doc';
          const textAlign = node.attrs?.textAlign;
          const hasCustomAlignment = allowsInlineHeadingHTML && textAlign && textAlign !== 'left';

          if (!hasCustomAlignment) {
            if (typeof parentStorage.markdown?.serialize === 'function') {
              parentStorage.markdown.serialize(state, node, parent);
              return;
            }

            const parsedLevel = Number.parseInt(String(node.attrs?.level ?? ''), 10);
            const level = Number.isFinite(parsedLevel) ? Math.max(1, Math.min(6, parsedLevel)) : 1;
            state.write(`${'#'.repeat(level)} `);
            state.renderInline(node);
            state.closeBlock(node);
            return;
          }

          const headingLevel = Math.max(1, Math.min(6, Number(node.attrs?.level) || 1));
          state.write(`<h${headingLevel} style="text-align: ${escapeHtmlAttr(textAlign)}">`);
          state.renderInline(node);
          state.write(`</h${headingLevel}>`);
          state.closeBlock(node);
        },
      },
    };
  },
});

const CiderHardBreak = HardBreak.extend({
  addStorage() {
    const parentStorage = this.parent?.() ?? {};

    return {
      ...parentStorage,
      markdown: {
        ...parentStorage.markdown,
        serialize(state, node, parent) {
          const parentTypeName = parent?.type?.name ?? '';
          const textAlign = parent?.attrs?.textAlign;
          const insideAlignedParagraph = parentTypeName === 'paragraph'
            && textAlign
            && textAlign !== 'left';

          if (insideAlignedParagraph) {
            state.write('<br />');
            return;
          }

          state.write('\\\\\n');
        },
      },
    };
  },
});

const CiderImage = Image.extend({
  addAttributes() {
    const parentAttributes = this.parent?.() ?? {};

    return {
      ...parentAttributes,
      width: {
        default: null,
        parseHTML: (element) => {
          const width = element.getAttribute('data-width') ?? element.getAttribute('width');
          return parsePositiveInt(width);
        },
        renderHTML: (attributes) => {
          const width = parsePositiveInt(attributes.width);
          if (!width) return {};
          return {
            width: String(width),
            'data-width': String(width),
          };
        },
      },
    };
  },

  addStorage() {
    const parentStorage = this.parent?.() ?? {};

    return {
      ...parentStorage,
      markdown: {
        ...parentStorage.markdown,
        serialize(state, node) {
          const width = parsePositiveInt(node.attrs.width);
          const alt = state.esc(node.attrs.alt || '');
          const src = String(node.attrs.src || '').replace(/[\(\)]/g, '\\$&');
          const title = node.attrs.title
            ? ` "${String(node.attrs.title).replace(/"/g, '\\"')}"`
            : '';

          if (!width) {
            state.write(`![${alt}](${src}${title})`);
            return;
          }

          const htmlSrc = escapeHtmlAttr(node.attrs.src || '');
          const htmlAlt = escapeHtmlAttr(node.attrs.alt || '');
          const htmlTitle = node.attrs.title ? ` title="${escapeHtmlAttr(node.attrs.title)}"` : '';
          state.write(`<img src="${htmlSrc}" alt="${htmlAlt}"${htmlTitle} width="${width}" data-width="${width}" />`);
        },
      },
    };
  },

  addNodeView() {
    return ({ editor, node, getPos }) => {
      let currentNode = node;
      const container = document.createElement('span');
      container.className = 'cider-image-node';
      container.contentEditable = 'false';

      const image = document.createElement('img');
      image.className = 'cider-image-element';
      image.draggable = false;

      const dragHandle = document.createElement('span');
      dragHandle.className = 'cider-image-drag-handle';
      dragHandle.setAttribute('data-drag-handle', '');
      dragHandle.title = 'Drag to move image';

      const resizeHandle = document.createElement('span');
      resizeHandle.className = 'cider-image-resize-handle';

      container.appendChild(dragHandle);
      container.appendChild(image);
      container.appendChild(resizeHandle);

      const updateImageFromNode = (imageNode) => {
        image.src = imageNode.attrs.src || '';
        image.alt = imageNode.attrs.alt || '';
        image.title = imageNode.attrs.title || '';

        const width = parsePositiveInt(imageNode.attrs.width);
        if (width) {
          image.style.width = `${width}px`;
        } else {
          image.style.removeProperty('width');
        }
      };

      const selectThisNode = () => {
        const pos = typeof getPos === 'function' ? getPos() : null;
        if (pos == null) return;
        const { state, dispatch } = editor.view;
        dispatch(state.tr.setSelection(NodeSelection.create(state.doc, pos)));
      };

      const persistWidth = (rawWidth) => {
        const pos = typeof getPos === 'function' ? getPos() : null;
        if (pos == null) return;
        const width = Math.max(IMAGE_RESIZE_MIN_WIDTH, Math.min(IMAGE_RESIZE_MAX_WIDTH, Math.round(rawWidth)));
        const attrs = {
          ...currentNode.attrs,
          width,
        };
        editor.view.dispatch(editor.view.state.tr.setNodeMarkup(pos, undefined, attrs));
      };

      let dropIndicator = null;

      const ensureDropIndicator = () => {
        if (dropIndicator) {
          return dropIndicator;
        }

        dropIndicator = document.createElement('div');
        dropIndicator.className = 'cider-image-drop-indicator';
        document.body.appendChild(dropIndicator);
        return dropIndicator;
      };

      const hideDropIndicator = () => {
        if (dropIndicator) {
          dropIndicator.style.display = 'none';
        }
      };

      const cleanupDropIndicator = () => {
        if (!dropIndicator) return;
        dropIndicator.remove();
        dropIndicator = null;
      };

      const resolveDropTargetPos = (sourcePos, clientX, clientY) => {
        const view = editor.view;
        const sourceNode = view.state.doc.nodeAt(sourcePos);
        if (!sourceNode || sourceNode.type !== currentNode.type) {
          return null;
        }

        const posAtCoords = view.posAtCoords({ left: clientX, top: clientY });
        if (!posAtCoords) {
          return null;
        }

        const sourceSize = sourceNode.nodeSize;
        const targetPos = posAtCoords.pos;
        if (targetPos >= sourcePos && targetPos <= sourcePos + sourceSize) {
          return null;
        }

        return targetPos;
      };

      const updateDropIndicator = (sourcePos, clientX, clientY) => {
        const targetPos = resolveDropTargetPos(sourcePos, clientX, clientY);
        if (targetPos == null) {
          hideDropIndicator();
          return null;
        }

        let coords;
        try {
          coords = editor.view.coordsAtPos(targetPos);
        } catch {
          hideDropIndicator();
          return null;
        }

        const indicator = ensureDropIndicator();
        const lineHeight = Number.parseFloat(
          window.getComputedStyle(editor.view.dom).lineHeight
        );
        const caretHeight = Number.isFinite(lineHeight) ? Math.max(16, lineHeight) : 20;

        indicator.style.display = 'block';
        indicator.style.left = `${Math.round(coords.left)}px`;
        indicator.style.top = `${Math.round(coords.top)}px`;
        indicator.style.height = `${Math.round(caretHeight)}px`;

        return targetPos;
      };

      const moveImageToPos = (sourcePos, rawTargetPos) => {
        if (!Number.isInteger(rawTargetPos)) {
          return false;
        }

        const view = editor.view;
        const state = view.state;
        const sourceNode = state.doc.nodeAt(sourcePos);

        if (!sourceNode || sourceNode.type !== currentNode.type) {
          return false;
        }

        const sourceSize = sourceNode.nodeSize;
        let targetPos = rawTargetPos;
        if (targetPos >= sourcePos && targetPos <= sourcePos + sourceSize) {
          return false;
        }

        let tr = state.tr.delete(sourcePos, sourcePos + sourceSize);
        targetPos = tr.mapping.map(targetPos, -1);
        targetPos = Math.max(0, Math.min(targetPos, tr.doc.content.size));

        try {
          tr = tr.insert(targetPos, sourceNode);
        } catch (error) {
          postEditorDiagnostic('image-drag', error?.message ?? 'Failed to drop image');
          return false;
        }

        try {
          tr = tr.setSelection(NodeSelection.create(tr.doc, targetPos));
        } catch {
          // Selection is best-effort after move.
        }

        view.dispatch(tr.scrollIntoView());
        return true;
      };

      const startResize = (event) => {
        if (!editor.isEditable) return;
        event.preventDefault();
        event.stopPropagation();
        selectThisNode();

        container.classList.add('is-resizing');

        const startX = event.clientX;
        const startWidth = image.getBoundingClientRect().width
          || parsePositiveInt(currentNode.attrs.width)
          || IMAGE_RESIZE_MIN_WIDTH;

        const onPointerMove = (moveEvent) => {
          const delta = moveEvent.clientX - startX;
          const nextWidth = Math.max(
            IMAGE_RESIZE_MIN_WIDTH,
            Math.min(IMAGE_RESIZE_MAX_WIDTH, startWidth + delta),
          );
          image.style.width = `${Math.round(nextWidth)}px`;
        };

        const onPointerUp = () => {
          window.removeEventListener('pointermove', onPointerMove);
          window.removeEventListener('pointerup', onPointerUp);
          container.classList.remove('is-resizing');
          persistWidth(image.getBoundingClientRect().width);
        };

        window.addEventListener('pointermove', onPointerMove);
        window.addEventListener('pointerup', onPointerUp);
      };

      const startMove = (event) => {
        if (!editor.isEditable) return;
        event.preventDefault();
        event.stopPropagation();
        selectThisNode();

        const sourcePos = typeof getPos === 'function' ? getPos() : null;
        if (sourcePos == null) {
          return;
        }

        const startX = event.clientX;
        const startY = event.clientY;
        let moved = false;
        let pendingDropTarget = null;
        container.classList.add('is-dragging');
        hideDropIndicator();

        const scrollHost = document.getElementById('editor');
        const edgeScrollThreshold = 24;
        const edgeScrollAmount = 12;

        const onPointerMove = (moveEvent) => {
          const deltaX = moveEvent.clientX - startX;
          const deltaY = moveEvent.clientY - startY;
          if (!moved && Math.hypot(deltaX, deltaY) >= 4) {
            moved = true;
          }

          if (moved) {
            pendingDropTarget = updateDropIndicator(
              sourcePos,
              moveEvent.clientX,
              moveEvent.clientY
            );
          }

          if (scrollHost) {
            const rect = scrollHost.getBoundingClientRect();
            if (moveEvent.clientY < rect.top + edgeScrollThreshold) {
              scrollHost.scrollTop -= edgeScrollAmount;
            } else if (moveEvent.clientY > rect.bottom - edgeScrollThreshold) {
              scrollHost.scrollTop += edgeScrollAmount;
            }
          }
        };

        const onPointerUp = (upEvent) => {
          window.removeEventListener('pointermove', onPointerMove);
          window.removeEventListener('pointerup', onPointerUp);
          container.classList.remove('is-dragging');
          hideDropIndicator();

          if (!moved) {
            return;
          }

          const fallbackTarget = resolveDropTargetPos(
            sourcePos,
            upEvent.clientX,
            upEvent.clientY
          );
          const didMove = moveImageToPos(
            sourcePos,
            pendingDropTarget ?? fallbackTarget
          );
          if (!didMove) {
            postEditorDiagnostic('image-drag', 'No valid drop target for image move');
          }
        };

        window.addEventListener('pointermove', onPointerMove);
        window.addEventListener('pointerup', onPointerUp);
      };

      dragHandle.addEventListener('pointerdown', startMove);

      image.addEventListener('mousedown', (event) => {
        if (!editor.isEditable) return;
        event.preventDefault();
        selectThisNode();
      });

      resizeHandle.addEventListener('pointerdown', startResize);
      updateImageFromNode(currentNode);

      return {
        dom: container,
        update(updatedNode) {
          if (updatedNode.type !== currentNode.type) return false;
          currentNode = updatedNode;
          updateImageFromNode(currentNode);
          return true;
        },
        selectNode() {
          container.classList.add('ProseMirror-selectednode');
        },
        deselectNode() {
          container.classList.remove('ProseMirror-selectednode');
          container.classList.remove('is-dragging');
          hideDropIndicator();
        },
        stopEvent(event) {
          return resizeHandle === event.target
            || resizeHandle.contains(event.target)
            || dragHandle === event.target
            || dragHandle.contains(event.target);
        },
        ignoreMutation() {
          return true;
        },
        destroy() {
          cleanupDropIndicator();
        },
      };
    };
  },
});

function decodeHtmlEntities(value) {
  const el = document.createElement('textarea');
  el.innerHTML = value;
  return el.value;
}

function normalizeIncomingMarkdown(value) {
  if (typeof value !== 'string') return '';

  let normalized = value.replace(fileProtocolPathPattern, '(/$1)');

  // Recovery path for previously saved escaped HTML content.
  if (escapedHtmlTagPattern.test(normalized)) {
    const decoded = decodeHtmlEntities(normalized);
    if (htmlTagPattern.test(decoded)) {
      normalized = decoded;
    }
  }

  return normalizeMarkdownForPersistence(normalized, {
    decodeEntities: decodeHtmlEntities,
  });
}

function getNormalizedMarkdown() {
  return normalizeMarkdownForPersistence(editor.storage.markdown.getMarkdown(), {
    decodeEntities: decodeHtmlEntities,
  });
}

// Shared slash command popup state.
window._slashPopup = {
  active: false,
  popup: null,
  items: [],
  command: null,
  selectedIndex: 0,
  updateUI: null,
};

const floatingToolbarActionGroups = {
  text: [
    {
      id: 'text-bold',
      label: 'B',
      title: 'Bold',
      run: currentEditor => currentEditor.chain().focus().toggleBold().run(),
      isActive: currentEditor => currentEditor.isActive('bold'),
    },
    {
      id: 'text-italic',
      label: 'I',
      title: 'Italic',
      run: currentEditor => currentEditor.chain().focus().toggleItalic().run(),
      isActive: currentEditor => currentEditor.isActive('italic'),
    },
    {
      id: 'text-underline',
      label: 'U',
      title: 'Underline',
      run: currentEditor => currentEditor.chain().focus().toggleUnderline().run(),
      isActive: currentEditor => currentEditor.isActive('underline'),
    },
    {
      id: 'text-bullets',
      label: '•',
      title: 'Bullet List',
      run: currentEditor => currentEditor.chain().focus().toggleBulletList().run(),
      isActive: currentEditor => currentEditor.isActive('bulletList'),
    },
    {
      id: 'text-numbered',
      label: '1.',
      title: 'Numbered List',
      run: currentEditor => currentEditor.chain().focus().toggleOrderedList().run(),
      isActive: currentEditor => currentEditor.isActive('orderedList'),
    },
    {
      id: 'text-task',
      label: '☑',
      title: 'Task List',
      run: currentEditor => currentEditor.chain().focus().toggleTaskList().run(),
      isActive: currentEditor => currentEditor.isActive('taskList'),
    },
  ],
  table: [
    {
      id: 'table-row-before',
      label: 'Row↑',
      title: 'Add Row Above',
      run: currentEditor => currentEditor.chain().focus().addRowBefore().run(),
      isEnabled: currentEditor => currentEditor.can().addRowBefore(),
    },
    {
      id: 'table-row-after',
      label: 'Row↓',
      title: 'Add Row Below',
      run: currentEditor => currentEditor.chain().focus().addRowAfter().run(),
      isEnabled: currentEditor => currentEditor.can().addRowAfter(),
    },
    {
      id: 'table-row-delete',
      label: '-Row',
      title: 'Delete Row',
      run: currentEditor => currentEditor.chain().focus().deleteRow().run(),
      isEnabled: currentEditor => currentEditor.can().deleteRow(),
    },
    {
      id: 'table-col-before',
      label: 'Col←',
      title: 'Add Column Left',
      run: currentEditor => currentEditor.chain().focus().addColumnBefore().run(),
      isEnabled: currentEditor => currentEditor.can().addColumnBefore(),
    },
    {
      id: 'table-col-after',
      label: 'Col→',
      title: 'Add Column Right',
      run: currentEditor => currentEditor.chain().focus().addColumnAfter().run(),
      isEnabled: currentEditor => currentEditor.can().addColumnAfter(),
    },
    {
      id: 'table-col-delete',
      label: '-Col',
      title: 'Delete Column',
      run: currentEditor => currentEditor.chain().focus().deleteColumn().run(),
      isEnabled: currentEditor => currentEditor.can().deleteColumn(),
    },
    {
      id: 'table-merge',
      label: 'Merge',
      title: 'Merge Cells',
      run: currentEditor => currentEditor.chain().focus().mergeCells().run(),
      isEnabled: currentEditor => currentEditor.can().mergeCells(),
    },
    {
      id: 'table-split',
      label: 'Split',
      title: 'Split Cell',
      run: currentEditor => currentEditor.chain().focus().splitCell().run(),
      isEnabled: currentEditor => currentEditor.can().splitCell(),
    },
    {
      id: 'table-delete',
      label: 'Del',
      title: 'Delete Table',
      run: currentEditor => currentEditor.chain().focus().deleteTable().run(),
      isEnabled: currentEditor => currentEditor.can().deleteTable(),
    },
  ],
};

const floatingToolbarActionLookup = new Map(
  Object.values(floatingToolbarActionGroups)
    .flat()
    .map(action => [action.id, action]),
);

function getFloatingToolbarActionState(action, currentEditor) {
  const isEnabled = action.isEnabled ? Boolean(action.isEnabled(currentEditor)) : true;
  const isActive = action.isActive ? Boolean(action.isActive(currentEditor)) : false;
  return { isEnabled, isActive };
}

window._floatingToolbar = {
  active: false,
  popup: null,
  context: null,
  frame: null,
  editor: null,
  updateRaf: null,
};

function postFloatingToolbarStateToNative() {
  const handler = window.webkit?.messageHandlers?.floatingToolbarState;
  if (!handler) return;

  const s = window._floatingToolbar;
  if (!s.active || !s.popup) {
    handler.postMessage({ active: false });
    return;
  }

  const rect = s.popup.getBoundingClientRect();
  handler.postMessage({
    active: true,
    left: rect.left,
    top: rect.top,
    right: rect.right,
    bottom: rect.bottom,
  });
}

function resolveFloatingToolbarContext(currentEditor) {
  if (!currentEditor?.isEditable || !currentEditor.isFocused) {
    return null;
  }

  if (isSlashPopupActive()) {
    return null;
  }

  if (currentEditor.isActive('table')) {
    return 'table';
  }

  if (!currentEditor.state.selection.empty) {
    return 'text';
  }

  return null;
}

function getFloatingToolbarAnchorRect(currentEditor) {
  const { from, to, empty } = currentEditor.state.selection;
  const start = currentEditor.view.coordsAtPos(from);
  const end = empty ? start : currentEditor.view.coordsAtPos(to);

  return {
    left: Math.min(start.left, end.left),
    right: Math.max(start.right, end.right),
    top: Math.min(start.top, end.top),
    bottom: Math.max(start.bottom, end.bottom),
  };
}

function createFloatingToolbarPopup() {
  const popup = document.createElement('div');
  popup.className = 'floating-editor-toolbar';
  popup.addEventListener('mousedown', (event) => {
    const button = event.target.closest('.floating-editor-toolbar-button');
    if (!button) return;

    event.preventDefault();
    event.stopPropagation();

    const actionId = button.dataset.action;
    if (typeof actionId === 'string') {
      runFloatingToolbarAction(actionId);
    }
  });

  document.body.appendChild(popup);
  return popup;
}

function hideFloatingToolbar() {
  const s = window._floatingToolbar;
  if (s.popup) {
    s.popup.style.display = 'none';
  }
  s.active = false;
  s.frame = null;
  postFloatingToolbarStateToNative();
}

function renderFloatingToolbar(context) {
  const s = window._floatingToolbar;
  if (!s.popup || !s.editor) return;

  const actions = floatingToolbarActionGroups[context] ?? [];
  s.popup.textContent = '';

  actions.forEach(action => {
    const { isEnabled, isActive } = getFloatingToolbarActionState(action, s.editor);
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'floating-editor-toolbar-button';
    if (isActive) {
      button.classList.add('is-active');
    }
    if (!isEnabled) {
      button.classList.add('is-disabled');
      button.disabled = true;
    }
    button.dataset.action = action.id;
    button.textContent = action.label;
    button.title = action.title;
    s.popup.appendChild(button);
  });

  s.context = context;
}

function positionFloatingToolbar(anchorRect) {
  const s = window._floatingToolbar;
  if (!s.popup) return;

  const margin = 8;
  const offset = 8;
  const viewportWidth = window.innerWidth;
  const viewportHeight = window.innerHeight;

  const popupWidth = s.popup.offsetWidth;
  const popupHeight = s.popup.offsetHeight;
  const anchorMidX = anchorRect.left + ((anchorRect.right - anchorRect.left) / 2);

  let left = anchorMidX - (popupWidth / 2);
  let top = anchorRect.top - popupHeight - offset;

  if (top < margin) {
    top = anchorRect.bottom + offset;
  }

  left = Math.max(margin, Math.min(left, viewportWidth - popupWidth - margin));
  top = Math.max(margin, Math.min(top, viewportHeight - popupHeight - margin));

  s.popup.style.left = `${Math.round(left)}px`;
  s.popup.style.top = `${Math.round(top)}px`;
}

function updateFloatingToolbar(forceRender = false) {
  const s = window._floatingToolbar;
  const currentEditor = s.editor;
  if (!currentEditor) return;

  const context = resolveFloatingToolbarContext(currentEditor);
  if (!context) {
    hideFloatingToolbar();
    return;
  }

  if (!s.popup) {
    s.popup = createFloatingToolbarPopup();
  }

  if (s.context !== context || forceRender) {
    renderFloatingToolbar(context);
  }

  const anchorRect = getFloatingToolbarAnchorRect(currentEditor);
  if (!anchorRect) {
    hideFloatingToolbar();
    return;
  }

  s.popup.style.display = 'flex';
  positionFloatingToolbar(anchorRect);
  s.active = true;
  s.frame = anchorRect;
  postFloatingToolbarStateToNative();
}

function requestFloatingToolbarUpdate(forceRender = false) {
  const s = window._floatingToolbar;
  if (s.updateRaf != null) {
    cancelAnimationFrame(s.updateRaf);
  }

  s.updateRaf = requestAnimationFrame(() => {
    s.updateRaf = null;
    updateFloatingToolbar(forceRender);
  });
}

function runFloatingToolbarAction(actionId) {
  const s = window._floatingToolbar;
  const currentEditor = s.editor;
  if (!currentEditor) return false;

  const action = floatingToolbarActionLookup.get(actionId);
  if (!action) return false;

  const { isEnabled } = getFloatingToolbarActionState(action, currentEditor);
  if (!isEnabled) {
    return false;
  }

  const didRun = action.run(currentEditor);
  requestFloatingToolbarUpdate(true);
  return Boolean(didRun);
}

function handleNativeFloatingToolbarClick(x, y) {
  const s = window._floatingToolbar;
  if (!s.active || !s.popup) {
    return false;
  }

  const hoveredButton = s.popup.querySelector('.floating-editor-toolbar-button:hover');
  if (hoveredButton) {
    return runFloatingToolbarAction(hoveredButton.dataset.action);
  }

  if (Number.isFinite(x) && Number.isFinite(y)) {
    const hit = document.elementFromPoint(x, y);
    const button = hit?.closest('.floating-editor-toolbar-button');
    if (button && s.popup.contains(button)) {
      return runFloatingToolbarAction(button.dataset.action);
    }
  }

  return false;
}

function initializeFloatingToolbar(currentEditor) {
  const s = window._floatingToolbar;
  s.editor = currentEditor;

  const scrollHost = document.getElementById('editor');
  if (scrollHost) {
    scrollHost.addEventListener('scroll', () => requestFloatingToolbarUpdate());
  }

  window.addEventListener('resize', () => requestFloatingToolbarUpdate());

  currentEditor.on('selectionUpdate', () => requestFloatingToolbarUpdate(true));
  currentEditor.on('focus', () => requestFloatingToolbarUpdate(true));
  currentEditor.on('blur', () => hideFloatingToolbar());

  requestFloatingToolbarUpdate(true);
}

const noteFindHighlightPluginKey = new PluginKey('noteFindHighlight');

function buildNoteFindDecorations(doc, matches, activeIndex) {
  const decorations = [];

  matches.forEach((match, index) => {
    if (!Number.isInteger(match.from) || !Number.isInteger(match.to) || match.to <= match.from) {
      return;
    }

    const from = Math.max(0, Math.min(match.from, doc.content.size));
    const to = Math.max(0, Math.min(match.to, doc.content.size));
    if (to <= from) {
      return;
    }

    decorations.push(
      Decoration.inline(
        from,
        to,
        {
          class: index === activeIndex ? 'cider-find-match-active' : 'cider-find-match',
        }
      )
    );
  });

  return DecorationSet.create(doc, decorations);
}

const NoteFindHighlights = Extension.create({
  name: 'noteFindHighlights',
  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: noteFindHighlightPluginKey,
        state: {
          init() {
            return DecorationSet.empty;
          },
          apply(transaction, oldDecorationSet, _oldState, newState) {
            const meta = transaction.getMeta(noteFindHighlightPluginKey);
            if (meta?.type === 'set') {
              return buildNoteFindDecorations(
                newState.doc,
                Array.isArray(meta.matches) ? meta.matches : [],
                Number.isInteger(meta.activeIndex) ? meta.activeIndex : -1
              );
            }

            if (meta?.type === 'clear') {
              return DecorationSet.empty;
            }

            if (transaction.docChanged) {
              return oldDecorationSet.map(transaction.mapping, transaction.doc);
            }

            return oldDecorationSet;
          },
        },
        props: {
          decorations(state) {
            return noteFindHighlightPluginKey.getState(state);
          },
        },
      }),
    ];
  },
});

window._noteFind = {
  query: '',
  matches: [],
  currentIndex: -1,
};

function normalizeNoteFindQuery(value) {
  return String(value ?? '').trim();
}

function buildFindTextSegments(doc) {
  const segments = [];
  let plainText = '';
  let pendingBlockBreak = false;

  doc.descendants((node, pos) => {
    if (node.isText && node.text) {
      if (pendingBlockBreak && plainText.length > 0 && !plainText.endsWith('\n')) {
        plainText += '\n';
      }
      pendingBlockBreak = false;

      const start = plainText.length;
      plainText += node.text;
      segments.push({
        start,
        end: plainText.length,
        from: pos,
      });
      return false;
    }

    if (node.type?.name === 'hardBreak') {
      plainText += '\n';
      pendingBlockBreak = false;
      return false;
    }

    if (node.isBlock && plainText.length > 0 && !plainText.endsWith('\n')) {
      pendingBlockBreak = true;
    }

    return true;
  });

  return { plainText, segments };
}

function mapFindRangeToDocRange(startIndex, endIndex, segments) {
  if (!Number.isInteger(startIndex) || !Number.isInteger(endIndex) || endIndex <= startIndex) {
    return null;
  }

  const startSegment = segments.find(
    segment => startIndex >= segment.start && startIndex < segment.end
  );
  const endSegment = segments.find(
    segment => (endIndex - 1) >= segment.start && (endIndex - 1) < segment.end
  );

  if (!startSegment || !endSegment) {
    return null;
  }

  const from = startSegment.from + (startIndex - startSegment.start);
  const to = endSegment.from + (endIndex - endSegment.start);
  if (!Number.isInteger(from) || !Number.isInteger(to) || to <= from) {
    return null;
  }

  return { from, to };
}

function collectNoteFindMatches(query) {
  const normalizedQuery = normalizeNoteFindQuery(query);
  if (!normalizedQuery) {
    return [];
  }

  const { plainText, segments } = buildFindTextSegments(editor.state.doc);
  if (!plainText || segments.length === 0) {
    return [];
  }

  const lowerText = plainText.toLocaleLowerCase();
  const lowerQuery = normalizedQuery.toLocaleLowerCase();

  const matches = [];
  let searchFrom = 0;
  while (searchFrom < lowerText.length) {
    const foundAt = lowerText.indexOf(lowerQuery, searchFrom);
    if (foundAt < 0) {
      break;
    }

    const mappedRange = mapFindRangeToDocRange(
      foundAt,
      foundAt + lowerQuery.length,
      segments
    );
    if (mappedRange) {
      matches.push(mappedRange);
    }

    searchFrom = foundAt + Math.max(1, lowerQuery.length);
  }

  return matches;
}

function noteFindPayload() {
  const state = window._noteFind;
  return {
    count: state.matches.length,
    index: state.currentIndex >= 0 ? (state.currentIndex + 1) : 0,
  };
}

function setNoteFindDecorations(matches, activeIndex) {
  if (!editor?.view) {
    return;
  }

  editor.view.dispatch(
    editor.state.tr.setMeta(noteFindHighlightPluginKey, {
      type: 'set',
      matches,
      activeIndex,
    })
  );
}

function clearNoteFindDecorations() {
  if (!editor?.view) {
    return;
  }

  editor.view.dispatch(
    editor.state.tr.setMeta(noteFindHighlightPluginKey, { type: 'clear' })
  );
}

function scrollToNoteFindMatch(match) {
  const scrollHost = document.getElementById('editor');
  if (!scrollHost || !match) {
    return;
  }

  let coords;
  try {
    coords = editor.view.coordsAtPos(match.from);
  } catch {
    return;
  }

  const hostRect = scrollHost.getBoundingClientRect();
  const padding = 24;
  if (coords.top < hostRect.top + padding || coords.top > hostRect.bottom - padding) {
    scrollHost.scrollTop += coords.top - (hostRect.top + hostRect.height / 2);
  }
}

function selectNoteFindMatch(index) {
  const state = window._noteFind;
  if (!Number.isInteger(index) || index < 0 || index >= state.matches.length) {
    return false;
  }

  const match = state.matches[index];
  try {
    const selection = TextSelection.create(editor.state.doc, match.from, match.to);
    editor.view.dispatch(editor.state.tr.setSelection(selection).scrollIntoView());
  } catch (error) {
    postEditorDiagnostic('find', error?.message ?? 'Failed to select find match');
    return false;
  }

  state.currentIndex = index;
  setNoteFindDecorations(state.matches, state.currentIndex);
  scrollToNoteFindMatch(match);
  requestFloatingToolbarUpdate(true);
  return true;
}

function refreshNoteFindMatches() {
  const state = window._noteFind;
  const previousMatch = state.currentIndex >= 0 ? state.matches[state.currentIndex] : null;
  state.matches = collectNoteFindMatches(state.query);

  if (state.matches.length === 0) {
    state.currentIndex = -1;
    clearNoteFindDecorations();
    return;
  }

  if (previousMatch) {
    const previousIndex = state.matches.findIndex(match =>
      match.from === previousMatch.from && match.to === previousMatch.to
    );
    if (previousIndex >= 0) {
      state.currentIndex = previousIndex;
      setNoteFindDecorations(state.matches, state.currentIndex);
      return;
    }
  }

  state.currentIndex = Math.min(
    Math.max(state.currentIndex, 0),
    state.matches.length - 1
  );
  setNoteFindDecorations(state.matches, state.currentIndex);
}

function noteFindSetQuery(query) {
  const state = window._noteFind;
  state.query = normalizeNoteFindQuery(query);

  if (!state.query) {
    state.matches = [];
    state.currentIndex = -1;
    clearNoteFindDecorations();
    return noteFindPayload();
  }

  refreshNoteFindMatches();
  if (state.matches.length > 0) {
    selectNoteFindMatch(0);
  }

  return noteFindPayload();
}

function noteFindMove(step) {
  const state = window._noteFind;
  if (!state.query) {
    return noteFindPayload();
  }

  refreshNoteFindMatches();
  if (state.matches.length === 0) {
    return noteFindPayload();
  }

  let nextIndex = state.currentIndex;
  if (nextIndex < 0) {
    nextIndex = step >= 0 ? 0 : state.matches.length - 1;
  } else {
    nextIndex = (nextIndex + step + state.matches.length) % state.matches.length;
  }

  selectNoteFindMatch(nextIndex);
  return noteFindPayload();
}

function clearNoteFindState() {
  const state = window._noteFind;
  state.query = '';
  state.matches = [];
  state.currentIndex = -1;
  clearNoteFindDecorations();
  return noteFindPayload();
}

const editor = new Editor({
  element: document.getElementById('editor'),
  extensions: [
    createSlashCommands(),
    StarterKit.configure({
      codeBlock: false,
      paragraph: false,
      heading: false,
      hardBreak: false,
    }),
    CiderTextAlign,
    CiderUnderline,
    CiderLink,
    CiderParagraph,
    CiderHeading,
    CiderHardBreak,
    NoteFindHighlights,
    TaskList,
    TaskItem.configure({ nested: true }),
    Table.configure({ resizable: false }),
    TableRow,
    TableCell,
    TableHeader,
    CiderImage.configure({ allowBase64: true, inline: true }),
    CodeBlockLowlight.configure({ lowlight }),
    Placeholder.configure({
      placeholder: 'Start writing, or type / for commands...',
    }),
    Markdown.configure({
      html: true,
      tightLists: false,
      transformPastedText: true,
      transformCopiedText: true,
    }),
  ],
  editorProps: {
    attributes: {
      class: 'tiptap-editor',
    },
    handleDOMEvents: {
      drop(view, event) {
        const files = event.dataTransfer?.files;
        if (!files || files.length === 0) return false;
        const imageFiles = Array.from(files).filter(f => f.type.startsWith('image/'));
        if (imageFiles.length === 0) return false;
        event.preventDefault();
        for (const file of imageFiles) {
          const reader = new FileReader();
          reader.onload = () => {
            const base64 = reader.result.split(',')[1];
            if (window.webkit?.messageHandlers?.imageDropped) {
              window.webkit.messageHandlers.imageDropped.postMessage(
                JSON.stringify({ data: base64, name: file.name })
              );
            }
          };
          reader.readAsDataURL(file);
        }
        return true;
      },
      paste(view, event) {
        const items = event.clipboardData?.items;
        if (!items) return false;
        for (const item of items) {
          if (item.type.startsWith('image/')) {
            event.preventDefault();
            const file = item.getAsFile();
            if (!file) continue;
            const reader = new FileReader();
            reader.onload = () => {
              const base64 = reader.result.split(',')[1];
              if (window.webkit?.messageHandlers?.imageDropped) {
                window.webkit.messageHandlers.imageDropped.postMessage(
                  JSON.stringify({ data: base64, name: file.name || 'pasted-image.png' })
                );
              }
            };
            reader.readAsDataURL(file);
            return true;
          }
        }
        return false;
      },
    },
  },
  onUpdate() {
    const markdown = getNormalizedMarkdown();
    if (window.webkit?.messageHandlers?.contentChanged) {
      window.webkit.messageHandlers.contentChanged.postMessage(markdown);
    }
    requestFloatingToolbarUpdate();
  },
  onCreate() {
    if (window.webkit?.messageHandlers?.editorReady) {
      window.webkit.messageHandlers.editorReady.postMessage('ready');
    }
  },
});

initializeFloatingToolbar(editor);

// Swift -> JS bridge API
window.editorAPI = {
  setContent(markdown) {
    clearNoteFindState();
    editor.commands.setContent(normalizeIncomingMarkdown(markdown), false, {
      preserveWhitespace: 'full',
    });
    requestFloatingToolbarUpdate(true);
  },
  getContent() {
    return getNormalizedMarkdown();
  },
  insertImage(src, alt) {
    editor.chain().focus().setImage({ src, alt: alt || '' }).run();
  },
  focus() {
    editor.commands.focus();
    requestFloatingToolbarUpdate(true);
  },
  blur() {
    editor.commands.blur();
    hideFloatingToolbar();
  },
  clear() {
    clearNoteFindState();
    editor.commands.clearContent();
    requestFloatingToolbarUpdate(true);
  },
  toggleBold() {
    return editor.chain().focus().toggleBold().run();
  },
  toggleItalic() {
    return editor.chain().focus().toggleItalic().run();
  },
  toggleUnderline() {
    return editor.chain().focus().toggleUnderline().run();
  },
  setTextAlign(alignment) {
    if (!supportedTextAlignments.includes(alignment)) {
      return false;
    }

    return editor.chain().focus().setTextAlign(alignment).run();
  },
  setLink(href) {
    if (typeof href !== 'string' || href.trim().length === 0) {
      return false;
    }

    return editor.chain().focus().setLink({ href: href.trim() }).run();
  },
  unsetLink() {
    return editor.chain().focus().unsetLink().run();
  },
  toggleBulletList() {
    return editor.chain().focus().toggleBulletList().run();
  },
  toggleOrderedList() {
    return editor.chain().focus().toggleOrderedList().run();
  },
  toggleTaskList() {
    return editor.chain().focus().toggleTaskList().run();
  },
  insertTable() {
    return editor.chain().focus().insertTable({ rows: 3, cols: 3, withHeaderRow: true }).run();
  },
  addColumnBefore() {
    return editor.chain().focus().addColumnBefore().run();
  },
  addColumnAfter() {
    return editor.chain().focus().addColumnAfter().run();
  },
  deleteColumn() {
    return editor.chain().focus().deleteColumn().run();
  },
  addRowBefore() {
    return editor.chain().focus().addRowBefore().run();
  },
  addRowAfter() {
    return editor.chain().focus().addRowAfter().run();
  },
  deleteRow() {
    return editor.chain().focus().deleteRow().run();
  },
  mergeCells() {
    return editor.chain().focus().mergeCells().run();
  },
  splitCell() {
    return editor.chain().focus().splitCell().run();
  },
  toggleHeaderRow() {
    return editor.chain().focus().toggleHeaderRow().run();
  },
  toggleHeaderColumn() {
    return editor.chain().focus().toggleHeaderColumn().run();
  },
  deleteTable() {
    return editor.chain().focus().deleteTable().run();
  },
  undo() {
    return editor.chain().focus().undo().run();
  },
  redo() {
    return editor.chain().focus().redo().run();
  },
  findSetQuery(query) {
    return noteFindSetQuery(query);
  },
  findNext() {
    return noteFindMove(1);
  },
  findPrevious() {
    return noteFindMove(-1);
  },
  findClear() {
    return clearNoteFindState();
  },
  handleNativeSlashClick(x, y) {
    return handleNativeSlashClick(x, y);
  },
  handleNativeSlashKey(key) {
    return handleNativeSlashKey(key);
  },
  isSlashPopupActive() {
    return isSlashPopupActive();
  },
  handleNativeFloatingToolbarClick(x, y) {
    return handleNativeFloatingToolbarClick(x, y);
  },
  isFloatingToolbarActive() {
    return Boolean(window._floatingToolbar?.active);
  },
};
