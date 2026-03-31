import React, { memo, useState, useCallback } from 'react';
import { Handle, Position, NodeResizer } from '@xyflow/react';

/**
 * Custom React Flow node for folder groups.
 * Acts as a parent container — child nodes live inside it.
 * Supports collapse/expand toggle.
 */
const FolderGroupNode = memo(({ data, selected, id }) => {
  const {
    folderName = 'Folder',
    icon = '📁',
    itemCount = 0,
    collapsed = false,
  } = data;

  const handleToggleCollapse = useCallback((e) => {
    e.stopPropagation();
    // Notify Swift about collapse toggle
    postMessage('folderToggleCollapse', JSON.stringify({
      folderId: id,
      folderName: data.folderName,
      collapsed: !collapsed,
    }));
  }, [id, data.folderName, collapsed]);

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
        <button
          className="folder-group-toggle"
          onClick={handleToggleCollapse}
          title={collapsed ? 'Expand' : 'Collapse'}
        >
          {collapsed ? '▸' : '▾'}
        </button>
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
