import React, { useState } from 'react';

const SidebarMockup = () => {
  const [isExpanded, setIsExpanded] = useState(true);
  const [layoutOption, setLayoutOption] = useState('A');
  const [stagedFiles, setStagedFiles] = useState([
    { name: 'report.pdf', icon: '📄' },
    { name: 'screenshot.png', icon: '🖼️' }
  ]);
  const [clipboardContent, setClipboardContent] = useState({
    type: 'text',
    preview: 'https://github.com/example/repo'
  });
  const [expandedApps, setExpandedApps] = useState(['Finder']);
  const [isDragOver, setIsDragOver] = useState(false);

  const pinnedApps = [
    { name: 'Finder', icon: '📁', color: '#4A90D9' },
    { name: 'Safari', icon: '🧭', color: '#5AC8FA' },
    { name: 'VS Code', icon: '💻', color: '#007ACC' },
    { name: 'Terminal', icon: '⬛', color: '#333' },
    { name: 'Messages', icon: '💬', color: '#34C759' },
  ];

  const openApps = [
    { 
      name: 'Finder', 
      icon: '📁',
      windows: ['Downloads', 'Documents']
    },
    { 
      name: 'Safari', 
      icon: '🧭',
      windows: ['GitHub - repo', 'Stack Overflow']
    },
    { 
      name: 'VS Code', 
      icon: '💻',
      windows: ['sidebar-app']
    },
  ];

  const toggleAppExpand = (appName) => {
    setExpandedApps(prev => 
      prev.includes(appName) 
        ? prev.filter(a => a !== appName)
        : [...prev, appName]
    );
  };

  const removeFile = (index) => {
    setStagedFiles(prev => prev.filter((_, i) => i !== index));
  };

  const Squircle = ({ app, size = 40 }) => (
    <div
      className="flex items-center justify-center cursor-pointer transition-transform hover:scale-110"
      style={{
        width: size,
        height: size,
        borderRadius: size * 0.22,
        backgroundColor: app.color || '#666',
        fontSize: size * 0.5,
      }}
      title={app.name}
    >
      {app.icon}
    </div>
  );

  const PinnedLaunchers = () => (
    <div className="p-3 border-b border-gray-700">
      <div className="text-xs text-gray-500 mb-2 font-medium">PINNED</div>
      <div className="flex gap-2 justify-center flex-wrap">
        {pinnedApps.map((app, i) => (
          <Squircle key={i} app={app} size={36} />
        ))}
      </div>
    </div>
  );

  const WindowList = () => (
    <div className="flex-1 overflow-y-auto p-2">
      <div className="text-xs text-gray-500 mb-2 px-1 font-medium">WINDOWS</div>
      {openApps.map((app, i) => (
        <div key={i} className="mb-1">
          <div 
            className="flex items-center gap-2 p-2 rounded-lg hover:bg-gray-700 cursor-pointer transition-colors"
            onClick={() => toggleAppExpand(app.name)}
          >
            <span className="text-lg">{app.icon}</span>
            <span className="text-sm text-gray-200 flex-1">{app.name}</span>
            {app.windows.length > 1 && (
              <span className="text-xs text-gray-500">
                {expandedApps.includes(app.name) ? '▼' : '▶'}
              </span>
            )}
          </div>
          {expandedApps.includes(app.name) && app.windows.map((win, j) => (
            <div 
              key={j}
              className="flex items-center gap-2 p-2 pl-8 rounded-lg hover:bg-gray-700 cursor-pointer text-sm text-gray-400 transition-colors"
            >
              <span className="text-xs">┗</span>
              <span className="truncate">{win}</span>
            </div>
          ))}
        </div>
      ))}
    </div>
  );

  const ClipboardPreview = () => (
    <div className="p-3 border-t border-gray-700">
      <div className="text-xs text-gray-500 mb-2 font-medium">CLIPBOARD</div>
      <div className="bg-gray-700 rounded-lg p-2 text-xs text-gray-300 truncate">
        {clipboardContent.type === 'text' ? '📋 ' : '🖼️ '}
        {clipboardContent.preview}
      </div>
    </div>
  );

  const DropZone = () => (
    <div className="p-3 border-t border-gray-700">
      <div className="flex items-center justify-between mb-2">
        <span className="text-xs text-gray-500 font-medium">DROP ZONE</span>
        {stagedFiles.length > 0 && (
          <button 
            className="text-xs text-red-400 hover:text-red-300 transition-colors"
            onClick={() => setStagedFiles([])}
          >
            Clear
          </button>
        )}
      </div>
      <div 
        className={`border-2 border-dashed rounded-lg p-3 transition-colors ${
          isDragOver 
            ? 'border-blue-400 bg-blue-900/30' 
            : 'border-gray-600 hover:border-gray-500'
        }`}
        onDragOver={(e) => { e.preventDefault(); setIsDragOver(true); }}
        onDragLeave={() => setIsDragOver(false)}
        onDrop={() => setIsDragOver(false)}
      >
        {stagedFiles.length === 0 ? (
          <div className="text-center text-gray-500 text-xs py-2">
            Drop files here
          </div>
        ) : (
          <div className="space-y-1">
            {stagedFiles.map((file, i) => (
              <div 
                key={i}
                className="flex items-center gap-2 p-1.5 bg-gray-700 rounded text-xs group"
              >
                <span>{file.icon}</span>
                <span className="flex-1 truncate text-gray-300">{file.name}</span>
                <button 
                  className="text-gray-500 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-opacity"
                  onClick={() => removeFile(i)}
                >
                  ✕
                </button>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );

  const Sidebar = () => (
    <div 
      className={`h-full bg-gray-800/95 backdrop-blur-xl flex flex-col transition-all duration-300 ${
        isExpanded ? 'w-56' : 'w-14'
      }`}
      style={{
        borderRadius: '0 12px 12px 0',
        boxShadow: '4px 0 24px rgba(0,0,0,0.4)',
      }}
    >
      {isExpanded ? (
        layoutOption === 'A' ? (
          <>
            <WindowList />
            <ClipboardPreview />
            <DropZone />
            <PinnedLaunchers />
          </>
        ) : (
          <>
            <PinnedLaunchers />
            <WindowList />
            <ClipboardPreview />
            <DropZone />
          </>
        )
      ) : (
        <div className="flex flex-col items-center py-3 gap-2">
          {pinnedApps.slice(0, 3).map((app, i) => (
            <Squircle key={i} app={app} size={32} />
          ))}
          <div className="text-gray-500 text-xs">•••</div>
        </div>
      )}
    </div>
  );

  return (
    <div className="min-h-screen bg-gradient-to-br from-purple-900 via-blue-900 to-teal-800 p-8">
      {/* Controls */}
      <div className="mb-6 flex gap-4 items-center">
        <h1 className="text-white text-xl font-semibold">Sidebar Mockup</h1>
        <div className="flex gap-2">
          <button
            className={`px-3 py-1.5 rounded-lg text-sm transition-colors ${
              layoutOption === 'A' 
                ? 'bg-white text-gray-800' 
                : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
            }`}
            onClick={() => setLayoutOption('A')}
          >
            Layout A (Launchers Bottom)
          </button>
          <button
            className={`px-3 py-1.5 rounded-lg text-sm transition-colors ${
              layoutOption === 'B' 
                ? 'bg-white text-gray-800' 
                : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
            }`}
            onClick={() => setLayoutOption('B')}
          >
            Layout B (Launchers Top)
          </button>
        </div>
        <button
          className="px-3 py-1.5 rounded-lg text-sm bg-gray-700 text-gray-300 hover:bg-gray-600 transition-colors"
          onClick={() => setIsExpanded(!isExpanded)}
        >
          {isExpanded ? 'Collapse' : 'Expand'}
        </button>
      </div>

      {/* Desktop simulation */}
      <div 
        className="relative bg-gray-900 rounded-2xl overflow-hidden"
        style={{ height: '600px' }}
      >
        {/* Fake menu bar */}
        <div className="h-7 bg-gray-800/80 flex items-center px-4 gap-2">
          <div className="flex gap-1.5">
            <div className="w-3 h-3 rounded-full bg-red-500" />
            <div className="w-3 h-3 rounded-full bg-yellow-500" />
            <div className="w-3 h-3 rounded-full bg-green-500" />
          </div>
          <span className="text-white text-xs font-medium ml-2">Finder</span>
        </div>

        {/* Desktop area with sidebar */}
        <div className="flex h-full">
          <Sidebar />
          
          {/* Desktop content */}
          <div className="flex-1 p-8">
            <div className="grid grid-cols-4 gap-4">
              {['📁 Projects', '📄 Notes.txt', '🖼️ Photo.png', '📦 Archive.zip'].map((item, i) => (
                <div 
                  key={i}
                  className="flex flex-col items-center gap-1 p-3 rounded-lg hover:bg-white/10 cursor-pointer transition-colors"
                  draggable
                >
                  <span className="text-3xl">{item.split(' ')[0]}</span>
                  <span className="text-white text-xs">{item.split(' ')[1]}</span>
                </div>
              ))}
            </div>
            
            <div className="mt-8 text-gray-400 text-sm">
              <p>↑ Try dragging these icons toward the sidebar drop zone</p>
              <p className="mt-2">Click app names in the sidebar to expand/collapse windows</p>
            </div>
          </div>
        </div>
        
        {/* Hover zone indicator */}
        <div 
          className="absolute left-0 top-7 bottom-0 w-1 bg-blue-500/30"
          title="Hover zone (in real app)"
        />
      </div>

      {/* Feature notes */}
      <div className="mt-6 grid grid-cols-3 gap-4 text-sm">
        <div className="bg-gray-800/50 rounded-xl p-4">
          <h3 className="text-white font-medium mb-2">Window List</h3>
          <p className="text-gray-400">Expandable tree of open apps and their windows. Click to focus, drag to group.</p>
        </div>
        <div className="bg-gray-800/50 rounded-xl p-4">
          <h3 className="text-white font-medium mb-2">Drop Zone</h3>
          <p className="text-gray-400">Stage files temporarily. Drag out to any app. Persists until cleared.</p>
        </div>
        <div className="bg-gray-800/50 rounded-xl p-4">
          <h3 className="text-white font-medium mb-2">Clipboard</h3>
          <p className="text-gray-400">Shows current clipboard contents. Click to quick-paste or view history.</p>
        </div>
      </div>
    </div>
  );
};

export default SidebarMockup;
