import { Editor, Extension, Mark } from '@tiptap/core';
import StarterKit from '@tiptap/starter-kit';
import TaskList from '@tiptap/extension-task-list';
import TaskItem from '@tiptap/extension-task-item';
import Table from '@tiptap/extension-table';
import TableRow from '@tiptap/extension-table-row';
import TableCell from '@tiptap/extension-table-cell';
import TableHeader from '@tiptap/extension-table-header';
import Image from '@tiptap/extension-image';
import CodeBlockLowlight from '@tiptap/extension-code-block-lowlight';
import Placeholder from '@tiptap/extension-placeholder';
import Paragraph from '@tiptap/extension-paragraph';
import { NodeSelection } from '@tiptap/pm/state';
import { Markdown } from 'tiptap-markdown';
import { common, createLowlight } from 'lowlight';
import {
  createSlashCommands,
  handleNativeSlashClick,
  handleNativeSlashKey,
  isSlashPopupActive,
} from './slash-commands.js';

const lowlight = createLowlight(common);

const escapedHtmlTagPattern = /&lt;(?:\/)?(?:p|h[1-6]|ul|ol|li|table|thead|tbody|tr|td|th|blockquote|pre|code|img|hr)\b/i;
const htmlTagPattern = /<(?:\/)?(?:p|h[1-6]|ul|ol|li|table|thead|tbody|tr|td|th|blockquote|pre|code|img|hr)\b/i;
const fileProtocolPathPattern = /\(file:\/\/\/([^)]+)\)/g;
const taskListItemSpacingPattern = /^(\s*(?:[-+*]|\d+[.)])\s+\[(?: |x|X)\])([ \t]+)(.*)$/;
const markdownFencePattern = /^(\s*)(`{3,}|~{3,})/;
const IMAGE_RESIZE_MIN_WIDTH = 80;
const IMAGE_RESIZE_MAX_WIDTH = 2000;
const supportedTextAlignments = ['left', 'center', 'right'];

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
      types: ['paragraph'],
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
    return {
      setTextAlign: (alignment) => ({ commands }) => {
        if (!this.options.alignments.includes(alignment)) {
          return false;
        }

        return this.options.types.some(type =>
          commands.updateAttributes(type, { textAlign: alignment })
        );
      },
      unsetTextAlign: () => ({ commands }) =>
        this.options.types.some(type => commands.updateAttributes(type, { textAlign: null })),
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
        serialize(state, node) {
          const textAlign = node.attrs?.textAlign;
          const hasCustomAlignment = textAlign && textAlign !== 'left';

          if (node.content.size === 0) {
            if (hasCustomAlignment) {
              state.write(`<p style="text-align: ${escapeHtmlAttr(textAlign)}"></p>`);
            } else {
              state.write('<p></p>');
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

      const handle = document.createElement('span');
      handle.className = 'cider-image-resize-handle';

      container.appendChild(image);
      container.appendChild(handle);

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

      image.addEventListener('mousedown', (event) => {
        if (!editor.isEditable) return;
        event.preventDefault();
        selectThisNode();
      });

      handle.addEventListener('pointerdown', startResize);
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
        },
        stopEvent(event) {
          return handle === event.target || handle.contains(event.target);
        },
        ignoreMutation() {
          return true;
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

function normalizeTaskListSpacing(markdown) {
  if (typeof markdown !== 'string' || markdown.length === 0) {
    return '';
  }

  const lines = markdown.split('\n');
  let activeFence = null;

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index];
    const fenceMatch = line.match(markdownFencePattern);
    if (fenceMatch) {
      const marker = fenceMatch[2][0];
      const markerLength = fenceMatch[2].length;

      if (!activeFence) {
        activeFence = { marker, markerLength };
      } else if (activeFence.marker === marker && markerLength >= activeFence.markerLength) {
        activeFence = null;
      }

      continue;
    }

    if (activeFence) continue;

    const taskLineMatch = line.match(taskListItemSpacingPattern);
    if (!taskLineMatch) continue;

    const [, marker, , content] = taskLineMatch;
    lines[index] = content.length === 0 ? marker : `${marker} ${content}`;
  }

  return lines.join('\n');
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

  return normalizeTaskListSpacing(normalized);
}

function getNormalizedMarkdown() {
  return normalizeTaskListSpacing(editor.storage.markdown.getMarkdown());
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

const editor = new Editor({
  element: document.getElementById('editor'),
  extensions: [
    createSlashCommands(),
    StarterKit.configure({
      codeBlock: false,
      paragraph: false,
    }),
    CiderTextAlign,
    CiderUnderline,
    CiderLink,
    CiderParagraph,
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
  },
  onCreate() {
    if (window.webkit?.messageHandlers?.editorReady) {
      window.webkit.messageHandlers.editorReady.postMessage('ready');
    }
  },
});

// Swift -> JS bridge API
window.editorAPI = {
  setContent(markdown) {
    editor.commands.setContent(normalizeIncomingMarkdown(markdown), false, {
      preserveWhitespace: 'full',
    });
  },
  getContent() {
    return getNormalizedMarkdown();
  },
  insertImage(src, alt) {
    editor.chain().focus().setImage({ src, alt: alt || '' }).run();
  },
  focus() {
    editor.commands.focus();
  },
  blur() {
    editor.commands.blur();
  },
  clear() {
    editor.commands.clearContent();
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
  undo() {
    return editor.chain().focus().undo().run();
  },
  redo() {
    return editor.chain().focus().redo().run();
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
};
