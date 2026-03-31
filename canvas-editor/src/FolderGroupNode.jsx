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
          <span className="folder-group-icon">{icon}</span>
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
