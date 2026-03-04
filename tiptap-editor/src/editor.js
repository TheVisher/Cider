import { Editor, Extension, Mark, mergeAttributes } from '@tiptap/core';
import StarterKit from '@tiptap/starter-kit';
import TaskList from '@tiptap/extension-task-list';
import TaskItem from '@tiptap/extension-task-item';
import Table from '@tiptap/extension-table';
import TableRow from '@tiptap/extension-table-row';
import TableCell from '@tiptap/extension-table-cell';
import TableHeader from '@tiptap/extension-table-header';
import Image from '@tiptap/extension-image';
import Heading from '@tiptap/extension-heading';
import Highlight from '@tiptap/extension-highlight';
import CodeBlockLowlight from '@tiptap/extension-code-block-lowlight';
import Placeholder from '@tiptap/extension-placeholder';
import Paragraph from '@tiptap/extension-paragraph';
import HardBreak from '@tiptap/extension-hard-break';
import { EditorState, NodeSelection, Plugin, PluginKey, TextSelection } from '@tiptap/pm/state';
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
const supportedFontSizes = ['12px', '14px', '16px', '18px', '24px', '32px'];
const parserTaskLeadingSpacePattern = /^ +/;
const webImageDropURLPattern = /\.(?:png|jpe?g|gif|webp|bmp|svg)(?:\?.*)?$/i;
const fontSizePattern = /^([1-9]\d{0,2})px$/i;
const editorBaseFontSizeCSSVariable = '--cider-editor-base-font-size';
const defaultEditorBaseFontSize = '14px';

let pendingImageInsertions = 0;
let pendingImageIndicator = null;
let pendingImageObserver = null;
let imagePreviewOverlay = null;

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

function normalizeFontSize(value) {
  const raw = String(value ?? '').trim();
  if (!raw) {
    return null;
  }

  const matched = raw.match(fontSizePattern);
  if (!matched) {
    return null;
  }

  const size = Number.parseInt(matched[1], 10);
  if (!Number.isFinite(size)) {
    return null;
  }

  const clamped = Math.max(10, Math.min(96, size));
  return `${clamped}px`;
}

function applyEditorBaseFontSize(value) {
  const normalized = normalizeFontSize(value) ?? defaultEditorBaseFontSize;
  document.documentElement.style.setProperty(editorBaseFontSizeCSSVariable, normalized);
  document.body.style.setProperty(editorBaseFontSizeCSSVariable, normalized);
  document.getElementById('editor')?.style?.setProperty(editorBaseFontSizeCSSVariable, normalized);
  return normalized;
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

  addStorage() {
    return {
      markdown: {
        serialize: {
          open(_state, mark) {
            return `<a href="${escapeHtmlAttr(mark.attrs.href || '')}">`;
          },
          close() {
            return '</a>';
          },
        },
        parse: {
          // handled by markdown-it + parseHTML
        },
      },
    };
  },

  addProseMirrorPlugins() {
    const markType = this.name;
    return [
      new Plugin({
        props: {
          handleClick(view, pos, event) {
            if (!event.metaKey) return false;

            const { doc } = view.state;
            const resolved = doc.resolve(pos);
            const marks = resolved.marks();
            const linkMark = marks.find(m => m.type.name === markType);
            if (!linkMark?.attrs?.href) return false;

            // Post to Swift to open in system browser (window.open is
            // blocked by WKWebView navigation policy)
            if (window.webkit?.messageHandlers?.linkClicked) {
              window.webkit.messageHandlers.linkClicked.postMessage(linkMark.attrs.href);
            }
            event.preventDefault();
            return true;
          },
        },
      }),
    ];
  },
});

const CiderFontSize = Mark.create({
  name: 'fontSize',

  addAttributes() {
    return {
      fontSize: {
        default: null,
        parseHTML: (element) => normalizeFontSize(element.style?.fontSize),
        renderHTML: (attributes) => {
          const size = normalizeFontSize(attributes.fontSize);
          if (!size) {
            return {};
          }

          return {
            style: `font-size: ${size}`,
          };
        },
      },
    };
  },

  parseHTML() {
    return [
      {
        style: 'font-size',
      },
    ];
  },

  renderHTML({ HTMLAttributes }) {
    return ['span', mergeAttributes(HTMLAttributes), 0];
  },

  addCommands() {
    return {
      setFontSize: (fontSize) => ({ commands }) => {
        const normalized = normalizeFontSize(fontSize);
        if (!normalized) {
          return false;
        }

        return commands.setMark(this.name, { fontSize: normalized });
      },
      unsetFontSize: () => ({ commands }) => commands.unsetMark(this.name),
    };
  },

  addStorage() {
    const parentStorage = this.parent?.() ?? {};

    return {
      ...parentStorage,
      markdown: {
        ...parentStorage.markdown,
        serialize: {
          open(_state, mark) {
            const size = normalizeFontSize(mark.attrs?.fontSize);
            if (!size) {
              return '';
            }

            return `<span style="font-size: ${escapeHtmlAttr(size)}">`;
          },
          close(_state, mark) {
            return normalizeFontSize(mark.attrs?.fontSize) ? '</span>' : '';
          },
        },
        parse: {
          // handled by markdown-it + parseHTML
        },
      },
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
            // Disable markdown escaping — content is inside an HTML block where
            // backslash escapes are literal text, causing doubling each round-trip.
            const origEsc = state.esc;
            state.esc = (str) => str;
            try {
              state.renderInline(node);
            } finally {
              state.esc = origEsc;
            }
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
          const origEsc = state.esc;
          state.esc = (str) => str;
          try {
            state.renderInline(node);
          } finally {
            state.esc = origEsc;
          }
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

          state.write('\\\n');
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
        serialize(state, node, _parent) {
          // Always serialize as <img> HTML (never ![]() markdown).
          // Reason: markdown ![]() inside a <p style="text-align: ..."> block is
          // treated as raw text by markdown-it (CommonMark HTML block rule), which
          // would cause the image to render as literal text on reload. Using <img>
          // avoids this for aligned paragraphs, and is equally stable for plain
          // paragraphs (markdown-it wraps a bare <img> in <p>, TipTap parses it
          // back to an inline image node correctly). Alignment is preserved by
          // CiderParagraph.serialize wrapping aligned content in <p style="...">.
          const htmlSrc = escapeHtmlAttr(node.attrs.src || '');
          const htmlAlt = escapeHtmlAttr(node.attrs.alt || '');
          const htmlTitle = node.attrs.title ? ` title="${escapeHtmlAttr(node.attrs.title)}"` : '';
          const width = parsePositiveInt(node.attrs.width);
          if (width) {
            state.write(`<img src="${htmlSrc}" alt="${htmlAlt}"${htmlTitle} width="${width}" data-width="${width}" />`);
          } else {
            state.write(`<img src="${htmlSrc}" alt="${htmlAlt}"${htmlTitle} />`);
          }
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

      image.addEventListener('click', (event) => {
        if (container.classList.contains('is-dragging') || container.classList.contains('is-resizing')) {
          return;
        }

        event.preventDefault();
        event.stopPropagation();
        openImagePreview(currentNode.attrs.src || '', currentNode.attrs.alt || '');
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

function convertMarkdownImagesInHtmlParagraphs(value) {
  // When a <p> HTML block contains markdown image syntax like ![alt](src),
  // markdown-it treats the entire block as raw HTML text (not markdown).
  // That means ![alt](src) renders as a literal string instead of an image.
  // Convert any such occurrences to <img> tags so TipTap creates proper image nodes.
  if (!value.includes('![')) return value;
  return value.replace(/<p(?:\s+[^>]*)?>[\s\S]*?<\/p>/g, (pBlock) => {
    if (!pBlock.includes('![')) return pBlock;
    return pBlock.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, (_, alt, src) => {
      return `<img src="${escapeHtmlAttr(src)}" alt="${escapeHtmlAttr(alt)}" />`;
    });
  });
}

function normalizeIncomingMarkdown(value) {
  if (typeof value !== 'string') return '';

  let normalized = value.replace(fileProtocolPathPattern, '(/$1)');

  // Strip accumulated backslash escapes inside aligned <p>/<h> HTML blocks.
  // The markdown serializer previously escaped backslashes and dots inside
  // HTML blocks where they're literal text, doubling them each round-trip.
  normalized = normalized.replace(
    /(<(?:p|h[1-6])\b[^>]*style="[^"]*text-align[^"]*"[^>]*>)([\s\S]*?)(<\/(?:p|h[1-6])>)/gi,
    (match, open, content, close) => {
      // Replace \+. after digits with just . (e.g. "1\\\\." → "1.")
      const cleaned = content.replace(/(\d+)\\+\./g, '$1.');
      return open + cleaned + close;
    },
  );

  // Convert markdown image syntax inside HTML <p> blocks to <img> tags.
  // Needed because markdown-it treats <p>...</p> as a raw HTML block,
  // so ![alt](src) inside renders as literal text rather than an image node.
  normalized = convertMarkdownImagesInHtmlParagraphs(normalized);

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

function ensurePendingImageIndicator() {
  if (pendingImageIndicator) {
    return pendingImageIndicator;
  }

  const container = document.createElement('div');
  container.className = 'cider-image-import-indicator';
  container.style.display = 'none';

  const spinner = document.createElement('span');
  spinner.className = 'cider-image-import-spinner';
  spinner.setAttribute('aria-hidden', 'true');

  const label = document.createElement('span');
  label.className = 'cider-image-import-label';
  label.textContent = 'Adding image...';

  container.appendChild(spinner);
  container.appendChild(label);
  document.body.appendChild(container);
  pendingImageIndicator = container;
  return container;
}

function updatePendingImageIndicator() {
  const indicator = ensurePendingImageIndicator();
  indicator.style.display = pendingImageInsertions > 0 ? 'inline-flex' : 'none';
}

function beginPendingImageInsertion() {
  pendingImageInsertions += 1;
  updatePendingImageIndicator();
}

function completePendingImageInsertion() {
  pendingImageInsertions = Math.max(0, pendingImageInsertions - 1);
  updatePendingImageIndicator();
}

function resetPendingImageInsertions() {
  pendingImageInsertions = 0;
  updatePendingImageIndicator();
}

function ensureImagePreviewOverlay() {
  if (imagePreviewOverlay) {
    return imagePreviewOverlay;
  }

  const backdrop = document.createElement('div');
  backdrop.className = 'cider-image-preview-overlay';
  backdrop.style.display = 'none';

  const image = document.createElement('img');
  image.className = 'cider-image-preview-image';
  image.draggable = false;

  const caption = document.createElement('div');
  caption.className = 'cider-image-preview-caption';

  backdrop.appendChild(image);
  backdrop.appendChild(caption);

  backdrop.addEventListener('click', (event) => {
    if (event.target === backdrop) {
      closeImagePreview();
    }
  });

  window.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') {
      return;
    }

    if (backdrop.style.display === 'none') {
      return;
    }

    event.preventDefault();
    closeImagePreview();
  });

  document.body.appendChild(backdrop);
  imagePreviewOverlay = {
    backdrop,
    image,
    caption,
  };
  return imagePreviewOverlay;
}

function openImagePreview(src, alt = '') {
  if (typeof src !== 'string' || src.length === 0) {
    return;
  }

  const overlay = ensureImagePreviewOverlay();
  overlay.image.src = src;
  overlay.image.alt = alt;
  overlay.caption.textContent = alt;
  overlay.caption.style.display = alt ? 'block' : 'none';
  overlay.backdrop.style.display = 'flex';
}

function closeImagePreview() {
  if (!imagePreviewOverlay) {
    return;
  }

  imagePreviewOverlay.backdrop.style.display = 'none';
}

function looksLikeWebImageDrop(event) {
  const transfer = event.dataTransfer;
  if (!transfer) {
    return false;
  }

  const types = Array.from(transfer.types || []);
  if (types.includes('text/uri-list') || types.includes('public.url') || types.includes('text/html')) {
    return true;
  }

  const uri = String(
    transfer.getData('text/uri-list')
    || transfer.getData('text/plain')
    || ''
  ).trim();
  const html = String(transfer.getData('text/html') || '');
  return webImageDropURLPattern.test(uri) || /<img\s/i.test(html);
}

function watchImageLoadState(imageElement) {
  if (!(imageElement instanceof HTMLImageElement)) {
    return;
  }

  if (imageElement.dataset.ciderImageLoadTracked === 'true') {
    return;
  }

  imageElement.dataset.ciderImageLoadTracked = 'true';

  if (imageElement.complete) {
    return;
  }

  beginPendingImageInsertion();
  const finish = () => {
    imageElement.removeEventListener('load', finish);
    imageElement.removeEventListener('error', finish);
    completePendingImageInsertion();
  };

  imageElement.addEventListener('load', finish, { once: true });
  imageElement.addEventListener('error', finish, { once: true });
}

function observeEditorImages() {
  const root = editor?.view?.dom;
  if (!root) {
    return;
  }

  root.querySelectorAll('img').forEach(watchImageLoadState);

  pendingImageObserver?.disconnect();
  pendingImageObserver = new MutationObserver((mutations) => {
    for (const mutation of mutations) {
      for (const node of mutation.addedNodes) {
        if (!(node instanceof Element)) {
          continue;
        }

        if (node instanceof HTMLImageElement) {
          watchImageLoadState(node);
          continue;
        }

        node.querySelectorAll?.('img').forEach(watchImageLoadState);
      }
    }
  });

  pendingImageObserver.observe(root, {
    childList: true,
    subtree: true,
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

// Post current formatting state to Swift for compact toolbar active indicators
function postEditorFormatState() {
  if (!window.webkit?.messageHandlers?.editorFormatState) return;
  const state = {
    bold: editor.isActive('bold'),
    italic: editor.isActive('italic'),
    underline: editor.isActive('underline'),
    strike: editor.isActive('strike'),
    highlight: editor.isActive('highlight'),
    link: editor.isActive('link'),
    bulletList: editor.isActive('bulletList'),
    orderedList: editor.isActive('orderedList'),
    taskList: editor.isActive('taskList'),
    blockquote: editor.isActive('blockquote'),
    codeBlock: editor.isActive('codeBlock'),
    inTable: editor.isActive('table'),
    heading: editor.isActive('heading', { level: 1 }) ? 1
           : editor.isActive('heading', { level: 2 }) ? 2
           : editor.isActive('heading', { level: 3 }) ? 3
           : 0,
    textAlign: editor.isActive({ textAlign: 'center' }) ? 'center'
             : editor.isActive({ textAlign: 'right' }) ? 'right'
             : 'left',
  };
  window.webkit.messageHandlers.editorFormatState.postMessage(state);
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

function stripTaskItemLeadingSpaceArtifacts() {
  const { state } = editor;
  let tr = state.tr;
  let changed = false;
  const taskPositions = [];

  state.doc.descendants((node, pos) => {
    if (node.type?.name === 'taskItem') {
      taskPositions.push(pos);
    }
  });

  for (const originalPos of taskPositions) {
    const mappedPos = tr.mapping.map(originalPos);
    const taskItem = tr.doc.nodeAt(mappedPos);
    if (!taskItem || taskItem.type?.name !== 'taskItem') {
      continue;
    }

    const paragraph = taskItem.firstChild;
    if (!paragraph || paragraph.type?.name !== 'paragraph' || paragraph.childCount === 0) {
      continue;
    }

    const firstInline = paragraph.child(0);
    if (!firstInline.isText || typeof firstInline.text !== 'string') {
      continue;
    }

    if (!parserTaskLeadingSpacePattern.test(firstInline.text)) {
      continue;
    }

    const trimmed = firstInline.text.slice(1);
    const textFrom = mappedPos + 2;
    const textTo = textFrom + firstInline.nodeSize;

    if (trimmed.length === 0) {
      tr = tr.delete(textFrom, textTo);
    } else {
      tr = tr.replaceWith(
        textFrom,
        textTo,
        state.schema.text(trimmed, firstInline.marks)
      );
    }
    changed = true;
  }

  if (!changed) {
    return;
  }

  tr = tr.setMeta('addToHistory', false);
  tr = tr.setMeta('preventUpdate', true);
  editor.view.dispatch(tr);
}

applyEditorBaseFontSize(defaultEditorBaseFontSize);

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
    CiderFontSize,
    CiderParagraph,
    CiderHeading,
    CiderHardBreak,
    NoteFindHighlights,
    TaskList,
    TaskItem.configure({ nested: true }),
    Table.configure({ resizable: true }),
    TableRow,
    TableCell,
    TableHeader,
    CiderImage.configure({ allowBase64: true, inline: true }),
    Highlight.configure({ multicolor: false }),
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
        const imageFiles = files ? Array.from(files).filter(f => f.type.startsWith('image/')) : [];
        if (imageFiles.length === 0) {
          if (looksLikeWebImageDrop(event)) {
            beginPendingImageInsertion();
            window.setTimeout(() => {
              completePendingImageInsertion();
            }, 4500);
          }
          return false;
        }
        event.preventDefault();
        for (const file of imageFiles) {
          beginPendingImageInsertion();
          window.requestAnimationFrame(() => {
            const reader = new FileReader();
            reader.onerror = () => {
              completePendingImageInsertion();
            };
            reader.onload = () => {
              const base64 = reader.result.split(',')[1];
              if (window.webkit?.messageHandlers?.imageDropped) {
                window.webkit.messageHandlers.imageDropped.postMessage(
                  JSON.stringify({ data: base64, name: file.name })
                );
              } else {
                completePendingImageInsertion();
              }
            };
            reader.readAsDataURL(file);
          });
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
            beginPendingImageInsertion();
            const reader = new FileReader();
            reader.onerror = () => {
              completePendingImageInsertion();
            };
            reader.onload = () => {
              const base64 = reader.result.split(',')[1];
              if (window.webkit?.messageHandlers?.imageDropped) {
                window.webkit.messageHandlers.imageDropped.postMessage(
                  JSON.stringify({ data: base64, name: file.name || 'pasted-image.png' })
                );
              } else {
                completePendingImageInsertion();
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
    postEditorFormatState();
  },
  onCreate() {
    if (window.webkit?.messageHandlers?.editorReady) {
      window.webkit.messageHandlers.editorReady.postMessage('ready');
    }
    ensurePendingImageIndicator();
    observeEditorImages();
  },
});

// Wire format state updates to editor events
editor.on('selectionUpdate', () => { postEditorFormatState(); });

// Toggle pointer cursor on links when Cmd key is held
document.addEventListener('keydown', (e) => {
  if (e.key === 'Meta') {
    editor.view.dom.classList.add('cmd-held');
  }
});
document.addEventListener('keyup', (e) => {
  if (e.key === 'Meta') {
    editor.view.dom.classList.remove('cmd-held');
  }
});
window.addEventListener('blur', () => {
  editor.view.dom.classList.remove('cmd-held');
});

// Forward Escape to Swift to close the editor when no popups/overlays are active.
window.addEventListener('keydown', (event) => {
  if (event.key !== 'Escape') return;

  // Let the image preview overlay handle its own Escape
  if (imagePreviewOverlay && imagePreviewOverlay.backdrop.style.display !== 'none') return;

  // Slash popup dismisses itself
  if (isSlashPopupActive()) return;

  if (window.webkit?.messageHandlers?.editorRequestClose) {
    event.preventDefault();
    window.webkit.messageHandlers.editorRequestClose.postMessage('close');
  }
});

function resetEditorPluginState() {
  const nextState = EditorState.create({
    schema: editor.state.schema,
    doc: editor.state.doc,
    selection: editor.state.selection,
    plugins: editor.state.plugins,
  });

  editor.view.updateState(nextState);
}

/**
 * After setContent(), ProseMirror's DOMParser may fail to read text-align
 * from <p style="text-align: center"> when the paragraph contains inline
 * images. This function repairs the document model by comparing the input
 * HTML's text-align values with the parsed document and applying any
 * missing alignments via a transaction.
 */
function repairTextAlignAfterParse(inputMarkdown) {
  if (!inputMarkdown.includes('text-align')) return;

  // Parse the input into a DOM tree to extract expected text-align values
  // for each top-level paragraph/heading block.
  const inputDOM = new DOMParser().parseFromString(
    `<body>${inputMarkdown}</body>`,
    'text/html',
  ).body;

  // Collect expected textAlign by top-level block index (only p and h1-h6).
  const expectedAligns = [];
  for (const child of inputDOM.childNodes) {
    if (child.nodeType !== Node.ELEMENT_NODE) {
      // Text nodes between blocks become paragraphs in ProseMirror.
      if (child.nodeType === Node.TEXT_NODE && child.textContent.trim()) {
        expectedAligns.push(null);
      }
      continue;
    }
    const tag = child.tagName.toLowerCase();
    if (tag === 'p' || /^h[1-6]$/.test(tag)) {
      const align = child.style?.textAlign;
      expectedAligns.push(
        align && supportedTextAlignments.includes(align) && align !== 'left'
          ? align
          : null,
      );
    } else {
      // Other block elements (table, blockquote, list, hr, etc.) also
      // count as a top-level block in ProseMirror.
      expectedAligns.push(null);
    }
  }

  if (!expectedAligns.some(Boolean)) return;

  // Walk the ProseMirror document's top-level children in parallel with
  // expectedAligns and apply any missing textAlign values.
  let { tr } = editor.state;
  let changed = false;
  const doc = editor.state.doc;
  const blockCount = Math.min(doc.childCount, expectedAligns.length);

  for (let i = 0; i < blockCount; i++) {
    const expected = expectedAligns[i];
    if (!expected) continue;

    const node = doc.child(i);
    if (
      (node.type.name === 'paragraph' || node.type.name === 'heading')
      && node.attrs.textAlign !== expected
    ) {
      // doc.child(i) offset = sum of sizes of children before i.
      let offset = 0;
      for (let j = 0; j < i; j++) {
        offset += doc.child(j).nodeSize;
      }
      tr = tr.setNodeMarkup(offset, undefined, {
        ...node.attrs,
        textAlign: expected,
      });
      changed = true;
    }
  }

  if (changed) {
    tr.setMeta('addToHistory', false);
    editor.view.dispatch(tr);
  }
}

function replaceEditorContent(markdown) {
  clearNoteFindState();
  closeImagePreview();
  resetPendingImageInsertions();
  const normalized = normalizeIncomingMarkdown(markdown);

  try {
    editor.commands.setContent(normalized, false, {
      preserveWhitespace: 'full',
    });
  } catch (err) {
    postEditorDiagnostic('setContent', 'error: ' + err.message + '\n' + err.stack);
    // Retry without preserveWhitespace as fallback
    try {
      editor.commands.setContent(normalized, false);
    } catch (retryErr) {
      postEditorDiagnostic('setContent', 'retry also failed: ' + retryErr.message);
    }
  }

  repairTextAlignAfterParse(normalized);
  stripTaskItemLeadingSpaceArtifacts();
  resetEditorPluginState();
}

// Swift -> JS bridge API
window.editorAPI = {
  setContent(markdown) {
    try {
      replaceEditorContent(markdown);
    } catch (err) {
      postEditorDiagnostic('setContent', 'API error: ' + err.message + '\n' + (err.stack || ''));
    }
  },
  getContent() {
    return getNormalizedMarkdown();
  },
  insertImage(src, alt) {
    const inserted = editor.chain().focus().setImage({ src, alt: alt || '' }).run();
    completePendingImageInsertion();
    return inserted;
  },
  focus() {
    editor.commands.focus();
  },
  blur() {
    editor.commands.blur();
  },
  clear() {
    replaceEditorContent('');
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
  setFontSize(fontSize) {
    const normalized = normalizeFontSize(fontSize);
    if (!normalized) {
      return false;
    }

    return editor.chain().focus().setFontSize(normalized).run();
  },
  unsetFontSize() {
    return editor.chain().focus().unsetFontSize().run();
  },
  setEditorBaseFontSize(fontSize) {
    const normalized = normalizeFontSize(fontSize);
    if (!normalized) {
      return false;
    }

    applyEditorBaseFontSize(normalized);
    return true;
  },
  getEditorBaseFontSize() {
    const value = getComputedStyle(document.documentElement)
      .getPropertyValue(editorBaseFontSizeCSSVariable)
      .trim();
    return normalizeFontSize(value) ?? defaultEditorBaseFontSize;
  },
  setLink(href) {
    if (typeof href !== 'string' || href.trim().length === 0) {
      return false;
    }

    const url = href.trim();
    const { from, to } = editor.state.selection;
    if (from === to) {
      // No text selected — insert the URL as linked text
      return editor
        .chain()
        .focus()
        .insertContent({
          type: 'text',
          text: url,
          marks: [{ type: 'link', attrs: { href: url } }],
        })
        .run();
    }

    return editor.chain().focus().setLink({ href: url }).run();
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
  insertTable(rows, cols) {
    rows = rows || 3;
    cols = cols || 3;
    return editor.chain().focus().insertTable({ rows, cols, withHeaderRow: false }).run();
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
  toggleStrike() {
    return editor.chain().focus().toggleStrike().run();
  },
  toggleBlockquote() {
    return editor.chain().focus().toggleBlockquote().run();
  },
  setHorizontalRule() {
    return editor.chain().focus().setHorizontalRule().run();
  },
  toggleHighlight() {
    return editor.chain().focus().toggleHighlight().run();
  },
  setHeading(level) {
    return editor.chain().focus().toggleHeading({ level }).run();
  },
  setParagraph() {
    return editor.chain().focus().setParagraph().run();
  },
  toggleCodeBlock() {
    return editor.chain().focus().toggleCodeBlock().run();
  },
};
