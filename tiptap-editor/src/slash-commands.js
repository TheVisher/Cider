import { Extension } from '@tiptap/core';
import Suggestion from '@tiptap/suggestion';
import { PluginKey } from '@tiptap/pm/state';

const slashSuggestionKey = new PluginKey('slashSuggestion');

const deleteTableItem = {
  title: 'Delete Table',
  icon: '\u232B',
  command: ({ editor, range }) => {
    if (editor.can().deleteTable()) {
      editor.chain().focus().deleteRange(range).deleteTable().run();
      return;
    }

    editor.chain().focus().deleteRange(range).run();
  },
};

const baseSlashItems = [
  {
    title: 'Heading 1',
    icon: 'H1',
    command: ({ editor, range }) => {
      editor.chain().focus().deleteRange(range).setHeading({ level: 1 }).run();
    },
  },
  {
    title: 'Heading 2',
    icon: 'H2',
    command: ({ editor, range }) => {
      editor.chain().focus().deleteRange(range).setHeading({ level: 2 }).run();
    },
  },
  {
    title: 'Heading 3',
    icon: 'H3',
    command: ({ editor, range }) => {
      editor.chain().focus().deleteRange(range).setHeading({ level: 3 }).run();
    },
  },
  {
    title: 'Bullet List',
    icon: '\u2022',
    command: ({ editor, range }) => {
      editor.chain().focus().deleteRange(range).toggleBulletList().run();
    },
  },
  {
    title: 'Numbered List',
    icon: '1.',
    command: ({ editor, range }) => {
      editor.chain().focus().deleteRange(range).toggleOrderedList().run();
    },
  },
  {
    title: 'Task List',
    icon: '\u2611',
    command: ({ editor, range }) => {
      editor.chain().focus().deleteRange(range).toggleTaskList().run();
    },
  },
  {
    title: 'Code Block',
    icon: '</>',
    command: ({ editor, range }) => {
      editor.chain().focus().deleteRange(range).toggleCodeBlock().run();
    },
  },
  {
    title: 'Table',
    icon: '\u2637',
    command: ({ editor, range }) => {
      editor.chain().focus().deleteRange(range).insertTable({ rows: 3, cols: 3, withHeaderRow: true }).run();
    },
  },
  {
    title: 'Image',
    icon: '\uD83D\uDDBC',
    command: ({ editor, range }) => {
      editor.chain().focus().deleteRange(range).run();
      if (window.webkit?.messageHandlers?.slashCommandImage) {
        window.webkit.messageHandlers.slashCommandImage.postMessage('pick');
      }
    },
  },
  {
    title: 'Blockquote',
    icon: '\u201C',
    command: ({ editor, range }) => {
      editor.chain().focus().deleteRange(range).toggleBlockquote().run();
    },
  },
  {
    title: 'Horizontal Rule',
    icon: '\u2014',
    command: ({ editor, range }) => {
      editor.chain().focus().deleteRange(range).setHorizontalRule().run();
    },
  },
];

function postPopupStateToNative() {
  const handler = window.webkit?.messageHandlers?.slashPopupState;
  if (!handler) return;

  const s = window._slashPopup;
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

function markSelection(index) {
  const s = window._slashPopup;
  s.selectedIndex = index;
  const rows = s.popup?.querySelectorAll('.slash-command-item');
  if (!rows) return;
  rows.forEach((row, rowIndex) => {
    row.classList.toggle('selected', rowIndex === index);
  });
}

function moveSelection(delta) {
  const s = window._slashPopup;
  if (!s.active) return false;
  if (!s.items.length) return true;

  s.selectedIndex = (s.selectedIndex + delta + s.items.length) % s.items.length;
  s.updateUI?.();
  return true;
}

function runSelectedItem() {
  const s = window._slashPopup;
  if (!s.active) return false;
  if (!s.items.length) return true;

  const item = s.items[s.selectedIndex] ?? s.items[0];
  if (item && s.command) {
    s.command(item);
  }

  return true;
}

function handleSlashKey(key) {
  switch (key) {
    case 'ArrowDown':
      return moveSelection(1);
    case 'ArrowUp':
      return moveSelection(-1);
    case 'Enter':
      return runSelectedItem();
    case 'Escape':
      return dismissPopup();
    default:
      return false;
  }
}

function dismissPopup() {
  const s = window._slashPopup;
  if (!s.active) return false;

  if (s.popup) {
    s.popup.remove();
  }

  s.active = false;
  s.popup = null;
  s.items = [];
  s.command = null;
  s.selectedIndex = 0;
  s.updateUI = null;
  postPopupStateToNative();
  return true;
}

function updatePopupUI() {
  const s = window._slashPopup;
  if (!s.popup) return;

  while (s.popup.firstChild) {
    s.popup.removeChild(s.popup.firstChild);
  }

  if (s.items.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'slash-command-empty';
    empty.textContent = 'No results';
    s.popup.appendChild(empty);
    postPopupStateToNative();
    return;
  }

  s.items.forEach((item, index) => {
    const el = document.createElement('div');
    el.className = 'slash-command-item';
    el.dataset.index = String(index);
    if (index === s.selectedIndex) el.classList.add('selected');

    const icon = document.createElement('span');
    icon.className = 'slash-command-icon';
    icon.textContent = item.icon;

    const title = document.createElement('span');
    title.className = 'slash-command-title';
    title.textContent = item.title;

    el.appendChild(icon);
    el.appendChild(title);

    // Keep mouse behavior for environments where DOM events work.
    el.addEventListener('mousedown', (event) => {
      event.preventDefault();
      markSelection(index);
      if (s.command) {
        s.command(item);
      }
    });

    el.addEventListener('mouseenter', () => {
      markSelection(index);
    });

    s.popup.appendChild(el);
  });

  const selected = s.popup.querySelector('.slash-command-item.selected');
  if (selected) {
    selected.scrollIntoView({ block: 'nearest' });
  }

  postPopupStateToNative();
}

function updatePosition(popup, clientRect) {
  if (!popup || !clientRect) return;

  const rect = clientRect();
  if (!rect) return;

  const margin = 8;
  const offset = 6;
  const viewportWidth = window.innerWidth;
  const viewportHeight = window.innerHeight;

  // Fit popup to the viewport and flip above the cursor when needed.
  const preferredTop = rect.bottom + offset;
  const spaceBelow = viewportHeight - preferredTop - margin;
  const spaceAbove = rect.top - offset - margin;
  const maxAvailable = Math.max(spaceBelow, spaceAbove, 140);
  const cappedHeight = Math.min(320, maxAvailable);
  popup.style.maxHeight = `${Math.floor(cappedHeight)}px`;

  const popupWidth = popup.offsetWidth;
  const popupHeight = popup.offsetHeight;

  let left = rect.left;
  let top = preferredTop;

  if (popupHeight > spaceBelow && spaceAbove > spaceBelow) {
    top = rect.top - popupHeight - offset;
  }

  left = Math.max(margin, Math.min(left, viewportWidth - popupWidth - margin));
  top = Math.max(margin, Math.min(top, viewportHeight - popupHeight - margin));

  popup.style.left = `${Math.floor(left)}px`;
  popup.style.top = `${Math.floor(top)}px`;
  postPopupStateToNative();
}

function createSlashCommandPopup() {
  return {
    onStart(props) {
      const s = window._slashPopup;
      s.active = true;
      s.items = props.items;
      s.command = props.command;
      s.selectedIndex = 0;
      s.updateUI = updatePopupUI;

      s.popup = document.createElement('div');
      s.popup.className = 'slash-command-popup';

      // Append to document.body to avoid clipping by #editor overflow.
      document.body.appendChild(s.popup);

      updatePopupUI();
      updatePosition(s.popup, props.clientRect);
    },

    onUpdate(props) {
      const s = window._slashPopup;
      s.active = true;
      s.items = props.items;
      s.command = props.command;
      s.selectedIndex = 0;

      if (s.popup && !s.popup.parentNode) {
        document.body.appendChild(s.popup);
      }

      updatePopupUI();
      updatePosition(s.popup, props.clientRect);
    },

    onKeyDown(props) {
      return handleSlashKey(props.event.key);
    },

    onExit() {
      dismissPopup();
    },
  };
}

export function handleNativeSlashClick(x, y) {
  const s = window._slashPopup;
  if (!s.active || !s.popup) {
    return false;
  }

  const runItemAtIndex = (index) => {
    if (!Number.isInteger(index) || index < 0 || index >= s.items.length) {
      return false;
    }
    markSelection(index);
    const item = s.items[index];
    if (item && s.command) {
      s.command(item);
    }
    return true;
  };

  // CSS :hover is reliable in WKWebView for this popup, so prefer it over manual geometry.
  const hoveredRow = s.popup.querySelector('.slash-command-item:hover');
  if (hoveredRow) {
    const hoverIndex = Number.parseInt(hoveredRow.dataset.index ?? '', 10);
    if (runItemAtIndex(hoverIndex)) {
      return true;
    }
  }

  // Fallback: hit-test with browser geometry.
  if (Number.isFinite(x) && Number.isFinite(y)) {
    const popupRect = s.popup.getBoundingClientRect();
    const insidePopup = x >= popupRect.left && x <= popupRect.right && y >= popupRect.top && y <= popupRect.bottom;
    if (!insidePopup) {
      return false;
    }

    const rowFromPoint = document.elementFromPoint(x, y)?.closest('.slash-command-item');
    if (rowFromPoint) {
      const pointIndex = Number.parseInt(rowFromPoint.dataset.index ?? '', 10);
      if (runItemAtIndex(pointIndex)) {
        return true;
      }
    }
  }

  // Swallow clicks within popup chrome/header to prevent cursor jumps.
  return true;
}

export function handleNativeSlashKey(key) {
  return handleSlashKey(key);
}

export function isSlashPopupActive() {
  return Boolean(window._slashPopup?.active);
}

export function createSlashCommands() {
  return Extension.create({
    name: 'slashCommands',
    priority: 10000,

    addOptions() {
      return {
        suggestion: {
          pluginKey: slashSuggestionKey,
          char: '/',
          command: ({ editor, range, props }) => {
            props.command({ editor, range });
          },
          items: ({ query, editor }) => {
            const slashItems = editor.can().deleteTable()
              ? [...baseSlashItems, deleteTableItem]
              : baseSlashItems;

            return slashItems.filter((item) =>
              item.title.toLowerCase().includes(query.toLowerCase())
            );
          },
          render: createSlashCommandPopup,
        },
      };
    },

    addKeyboardShortcuts() {
      return {
        ArrowDown: () => moveSelection(1),
        ArrowUp: () => moveSelection(-1),
        Enter: () => runSelectedItem(),
        Escape: () => dismissPopup(),
        'Mod-Shift-Backspace': ({ editor }) => {
          if (!editor.can().deleteTable()) return false;
          return editor.chain().focus().deleteTable().run();
        },
      };
    },

    addProseMirrorPlugins() {
      return [
        Suggestion({
          editor: this.editor,
          ...this.options.suggestion,
        }),
      ];
    },
  });
}
