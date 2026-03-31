import React, { memo, useCallback } from 'react';
import { Handle, Position, NodeResizer } from '@xyflow/react';

const LAYOUT_MODES = ['grid', 'list', 'masonry'];

const LayoutIcons = {
  grid: (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="currentColor">
      <rect x="0" y="0" width="6" height="6" rx="1" />
      <rect x="8" y="0" width="6" height="6" rx="1" />
      <rect x="0" y="8" width="6" height="6" rx="1" />
      <rect x="8" y="8" width="6" height="6" rx="1" />
    </svg>
  ),
  list: (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="currentColor">
      <rect x="0" y="0" width="14" height="3" rx="1" />
      <rect x="0" y="5.5" width="14" height="3" rx="1" />
      <rect x="0" y="11" width="14" height="3" rx="1" />
    </svg>
  ),
  masonry: (
    <svg width="14" height="14" viewBox="0 0 14 14" fill="currentColor">
      <rect x="0" y="0" width="6" height="8" rx="1" />
      <rect x="8" y="0" width="6" height="5" rx="1" />
      <rect x="0" y="10" width="6" height="4" rx="1" />
      <rect x="8" y="7" width="6" height="7" rx="1" />
    </svg>
  ),
};

/**
 * Custom React Flow node for folder groups.
 * Acts as a parent container — child nodes live inside it.
 * Supports collapse/expand toggle and layout mode switching.
 */
const FolderGroupNode = memo(({ data, selected, id }) => {
  const {
    folderName = 'Folder',
    icon = '📁',
    itemCount = 0,
    collapsed = false,
    layoutMode = 'grid',
  } = data;

  const handleToggleCollapse = useCallback((e) => {
    e.stopPropagation();
    postMessage('folderToggleCollapse', JSON.stringify({
      folderId: id,
      folderName: data.folderName,
      collapsed: !collapsed,
    }));
  }, [id, data.folderName, collapsed]);

  const handleCycleLayout = useCallback((e) => {
    e.stopPropagation();
    const currentIndex = LAYOUT_MODES.indexOf(layoutMode);
    const nextMode = LAYOUT_MODES[(currentIndex + 1) % LAYOUT_MODES.length];
    postMessage('folderLayoutChanged', JSON.stringify({
      folderId: id,
      layoutMode: nextMode,
    }));
  }, [id, layoutMode]);

  return (
    <div className={`folder-group ${selected ? 'selected' : ''} ${collapsed ? 'collapsed' : ''}`}>
      <NodeResizer
        minWidth={300}
        minHeight={collapsed ? 50 : 200}
        isVisible={selected}
        lineClassName="folder-group-resize-line"
        handleClassName="folder-group-resize-handle"
      />

      {/* Folder header */}
      <div className="folder-group-header">
        <div className="folder-group-title">
          <svg className="folder-group-icon" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/>
          </svg>
          <span className="folder-group-name">{folderName}</span>
          <span className="folder-group-count">{itemCount}</span>
        </div>
        <div className="folder-group-controls">
          {!collapsed && (
            <button
              className="folder-group-layout-btn"
              onClick={handleCycleLayout}
              title={`Layout: ${layoutMode}`}
            >
              {LayoutIcons[layoutMode]}
            </button>
          )}
          <button
            className="folder-group-toggle"
            onClick={handleToggleCollapse}
            title={collapsed ? 'Expand' : 'Collapse'}
          >
            {collapsed ? '▸' : '▾'}
          </button>
        </div>
      </div>

      {/* Connection handles */}
      <Handle type="target" position={Position.Top} className="card-handle" />
      <Handle type="source" position={Position.Bottom} className="card-handle" />
    </div>
  );
});

FolderGroupNode.displayName = 'FolderGroupNode';

function postMessage(name, data) {
  const handler = window.webkit?.messageHandlers?.[name];
  if (handler) {
    handler.postMessage(data ?? '');
  }
}

export default FolderGroupNode;
