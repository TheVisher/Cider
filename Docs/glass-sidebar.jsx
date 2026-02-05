import React, { useState } from 'react';

const GlassComponents = () => {
  const [hoveredComponent, setHoveredComponent] = useState(null);
  const [launcherPosition, setLauncherPosition] = useState('top');
  const [stagedFiles, setStagedFiles] = useState([
    { name: 'report.pdf', icon: '📄' },
    { name: 'screenshot.png', icon: '🖼️' }
  ]);
  const [expandedApps, setExpandedApps] = useState(['Finder']);
  const [clipboardHistory, setClipboardHistory] = useState([
    { type: 'text', content: 'https://github.com/example/repo', time: '2m ago' },
    { type: 'image', content: 'Screenshot', time: '5m ago' },
    { type: 'text', content: 'npm install sidebar-app', time: '12m ago' },
  ]);

  const pinnedApps = [
    { name: 'Finder', icon: '📁', color: '#4A90D9' },
    { name: 'Safari', icon: '🧭', color: '#5AC8FA' },
    { name: 'VS Code', icon: '💻', color: '#007ACC' },
    { name: 'Terminal', icon: '⬛', color: '#1a1a1a' },
    { name: 'Messages', icon: '💬', color: '#34C759' },
  ];

  const openApps = [
    { name: 'Finder', icon: '📁', windows: ['Downloads', 'Documents', 'Applications'] },
    { name: 'Safari', icon: '🧭', windows: ['GitHub - repo', 'Stack Overflow', 'Apple Developer'] },
    { name: 'VS Code', icon: '💻', windows: ['sidebar-app'] },
    { name: 'Figma', icon: '🎨', windows: ['Sidebar Design v2'] },
  ];

  const toggleAppExpand = (appName) => {
    setExpandedApps(prev => 
      prev.includes(appName) 
        ? prev.filter(a => a !== appName)
        : [...prev, appName]
    );
  };

  // Calculate sizes based on hover state
  const getComponentSize = (componentName) => {
    if (!hoveredComponent) return 'normal';
    if (hoveredComponent === componentName) return 'expanded';
    return 'contracted';
  };

  const sizeStyles = {
    expanded: {
      scale: 1,
      opacity: 1,
      maxHeight: '400px',
    },
    normal: {
      scale: 1,
      opacity: 0.95,
      maxHeight: '180px',
    },
    contracted: {
      scale: 0.92,
      opacity: 0.6,
      maxHeight: '100px',
    }
  };

  // Glass component wrapper
  const GlassPanel = ({ children, name, className = '' }) => {
    const size = getComponentSize(name);
    const styles = sizeStyles[size];
    
    return (
      <div
        className={`relative overflow-hidden transition-all duration-300 ease-out ${className}`}
        style={{
          background: 'linear-gradient(135deg, rgba(255,255,255,0.12) 0%, rgba(255,255,255,0.05) 100%)',
          backdropFilter: 'blur(40px) saturate(180%)',
          WebkitBackdropFilter: 'blur(40px) saturate(180%)',
          borderRadius: '16px',
          border: '1px solid rgba(255,255,255,0.18)',
          boxShadow: `
            0 8px 32px rgba(0,0,0,0.3),
            inset 0 1px 0 rgba(255,255,255,0.2),
            inset 0 -1px 0 rgba(0,0,0,0.1)
          `,
          transform: `scale(${styles.scale})`,
          opacity: styles.opacity,
          maxHeight: styles.maxHeight,
        }}
        onMouseEnter={() => setHoveredComponent(name)}
        onMouseLeave={() => setHoveredComponent(null)}
      >
        {/* Subtle inner glow */}
        <div 
          className="absolute inset-0 pointer-events-none"
          style={{
            background: 'radial-gradient(ellipse at top, rgba(255,255,255,0.1) 0%, transparent 60%)',
          }}
        />
        <div className="relative z-10">
          {children}
        </div>
      </div>
    );
  };

  const Squircle = ({ app, size = 40 }) => (
    <div
      className="flex items-center justify-center cursor-pointer transition-all duration-200 hover:scale-110 hover:shadow-lg"
      style={{
        width: size,
        height: size,
        borderRadius: size * 0.22,
        background: `linear-gradient(145deg, ${app.color}, ${app.color}dd)`,
        fontSize: size * 0.45,
        boxShadow: '0 2px 8px rgba(0,0,0,0.3)',
      }}
      title={app.name}
    >
      {app.icon}
    </div>
  );

  const LaunchersComponent = () => (
    <GlassPanel name="launchers" className="p-3">
      <div className="flex gap-2 justify-center">
        {pinnedApps.map((app, i) => (
          <Squircle key={i} app={app} size={38} />
        ))}
      </div>
      {hoveredComponent === 'launchers' && (
        <div className="mt-2 pt-2 border-t border-white/10">
          <div className="text-[10px] text-white/40 text-center">Drag to reorder • Right-click to remove</div>
        </div>
      )}
    </GlassPanel>
  );

  const WindowsComponent = () => {
    const size = getComponentSize('windows');
    const isExpanded = size === 'expanded';
    
    return (
      <GlassPanel name="windows" className="p-2">
        <div className="overflow-y-auto" style={{ maxHeight: isExpanded ? '340px' : '140px' }}>
          {openApps.map((app, i) => (
            <div key={i} className="mb-0.5">
              <div 
                className="flex items-center gap-2 p-1.5 rounded-lg hover:bg-white/10 cursor-pointer transition-colors"
                onClick={() => toggleAppExpand(app.name)}
              >
                <span className="text-base">{app.icon}</span>
                <span className="text-xs text-white/90 flex-1 font-medium">{app.name}</span>
                <span className="text-[10px] text-white/40 bg-white/10 px-1.5 py-0.5 rounded">
                  {app.windows.length}
                </span>
              </div>
              {expandedApps.includes(app.name) && isExpanded && app.windows.map((win, j) => (
                <div 
                  key={j}
                  className="flex items-center gap-2 py-1 px-2 ml-5 rounded hover:bg-white/10 cursor-pointer text-[11px] text-white/60 transition-colors group"
                >
                  <span className="w-1.5 h-1.5 rounded-full bg-white/30" />
                  <span className="truncate flex-1">{win}</span>
                  <span className="opacity-0 group-hover:opacity-100 text-white/40 transition-opacity">◉</span>
                </div>
              ))}
            </div>
          ))}
        </div>
        {isExpanded && (
          <div className="mt-2 pt-2 border-t border-white/10 flex gap-1 justify-center">
            <button className="text-[10px] text-white/50 hover:text-white/80 px-2 py-1 rounded hover:bg-white/10 transition-colors">
              Group Selected
            </button>
            <button className="text-[10px] text-white/50 hover:text-white/80 px-2 py-1 rounded hover:bg-white/10 transition-colors">
              Tile All
            </button>
          </div>
        )}
      </GlassPanel>
    );
  };

  const ClipboardComponent = () => {
    const size = getComponentSize('clipboard');
    const isExpanded = size === 'expanded';
    
    return (
      <GlassPanel name="clipboard" className="p-2">
        <div className="space-y-1">
          {clipboardHistory.slice(0, isExpanded ? 5 : 1).map((item, i) => (
            <div 
              key={i}
              className={`flex items-center gap-2 p-2 rounded-lg cursor-pointer transition-colors ${
                i === 0 ? 'bg-white/15' : 'hover:bg-white/10'
              }`}
            >
              <span className="text-sm">{item.type === 'text' ? '📋' : '🖼️'}</span>
              <span className="text-xs text-white/80 flex-1 truncate">{item.content}</span>
              {isExpanded && (
                <span className="text-[10px] text-white/30">{item.time}</span>
              )}
            </div>
          ))}
        </div>
        {isExpanded && (
          <div className="mt-2 pt-2 border-t border-white/10">
            <button className="w-full text-[10px] text-white/50 hover:text-white/80 py-1 rounded hover:bg-white/10 transition-colors">
              View Full History
            </button>
          </div>
        )}
      </GlassPanel>
    );
  };

  const DropZoneComponent = () => {
    const [isDragOver, setIsDragOver] = useState(false);
    const size = getComponentSize('dropzone');
    const isExpanded = size === 'expanded';
    
    return (
      <GlassPanel name="dropzone" className="p-2">
        <div 
          className={`border border-dashed rounded-lg p-2 transition-all ${
            isDragOver 
              ? 'border-blue-400 bg-blue-500/20' 
              : 'border-white/20 hover:border-white/30'
          }`}
          onDragOver={(e) => { e.preventDefault(); setIsDragOver(true); }}
          onDragLeave={() => setIsDragOver(false)}
          onDrop={() => setIsDragOver(false)}
        >
          {stagedFiles.length === 0 ? (
            <div className="text-center text-white/40 text-[11px] py-2">
              Drop files to stage
            </div>
          ) : (
            <div className="space-y-1">
              {stagedFiles.slice(0, isExpanded ? 10 : 2).map((file, i) => (
                <div 
                  key={i}
                  className="flex items-center gap-2 p-1.5 bg-white/10 rounded text-xs group cursor-grab active:cursor-grabbing"
                  draggable
                >
                  <span>{file.icon}</span>
                  <span className="flex-1 truncate text-white/80">{file.name}</span>
                  <button 
                    className="text-white/30 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-all text-[10px]"
                    onClick={() => setStagedFiles(prev => prev.filter((_, idx) => idx !== i))}
                  >
                    ✕
                  </button>
                </div>
              ))}
              {!isExpanded && stagedFiles.length > 2 && (
                <div className="text-[10px] text-white/40 text-center">
                  +{stagedFiles.length - 2} more
                </div>
              )}
            </div>
          )}
        </div>
        {isExpanded && stagedFiles.length > 0 && (
          <div className="mt-2 flex justify-between items-center">
            <span className="text-[10px] text-white/40">{stagedFiles.length} staged</span>
            <button 
              className="text-[10px] text-red-400/70 hover:text-red-400 transition-colors"
              onClick={() => setStagedFiles([])}
            >
              Clear All
            </button>
          </div>
        )}
      </GlassPanel>
    );
  };

  const componentsOrder = launcherPosition === 'top' 
    ? ['launchers', 'windows', 'clipboard', 'dropzone']
    : ['windows', 'clipboard', 'dropzone', 'launchers'];

  const componentMap = {
    launchers: <LaunchersComponent key="launchers" />,
    windows: <WindowsComponent key="windows" />,
    clipboard: <ClipboardComponent key="clipboard" />,
    dropzone: <DropZoneComponent key="dropzone" />,
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-purple-900 via-blue-900 to-teal-800 relative overflow-hidden">
      {/* Fake desktop background */}
      <div 
        className="absolute inset-0 opacity-60"
        style={{
          backgroundImage: `url("data:image/svg+xml,%3Csvg width='60' height='60' viewBox='0 0 60 60' xmlns='http://www.w3.org/2000/svg'%3E%3Cg fill='none' fill-rule='evenodd'%3E%3Cg fill='%23ffffff' fill-opacity='0.03'%3E%3Cpath d='M36 34v-4h-2v4h-4v2h4v4h2v-4h4v-2h-4zm0-30V0h-2v4h-4v2h4v4h2V6h4V4h-4zM6 34v-4H4v4H0v2h4v4h2v-4h4v-2H6zM6 4V0H4v4H0v2h4v4h2V6h4V4H6z'/%3E%3C/g%3E%3C/g%3E%3C/svg%3E")`,
        }}
      />
      
      {/* Controls */}
      <div className="relative z-20 p-6">
        <div className="flex items-center gap-4 mb-4">
          <h1 className="text-white text-xl font-semibold">Floating Glass Components</h1>
          <div className="flex gap-2">
            <button
              className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-all ${
                launcherPosition === 'top' 
                  ? 'bg-white/20 text-white' 
                  : 'bg-white/5 text-white/60 hover:bg-white/10'
              }`}
              onClick={() => setLauncherPosition('top')}
            >
              Launchers Top
            </button>
            <button
              className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-all ${
                launcherPosition === 'bottom' 
                  ? 'bg-white/20 text-white' 
                  : 'bg-white/5 text-white/60 hover:bg-white/10'
              }`}
              onClick={() => setLauncherPosition('bottom')}
            >
              Launchers Bottom
            </button>
          </div>
        </div>
        <p className="text-white/50 text-sm">Hover over each component to see it expand while others contract</p>
      </div>

      {/* Desktop simulation area */}
      <div className="relative mx-6 rounded-2xl overflow-hidden bg-black/30" style={{ height: '650px' }}>
        {/* Fake menu bar */}
        <div className="h-7 bg-black/40 backdrop-blur-md flex items-center px-4 gap-2">
          <div className="flex gap-1.5">
            <div className="w-3 h-3 rounded-full bg-red-500/80" />
            <div className="w-3 h-3 rounded-full bg-yellow-500/80" />
            <div className="w-3 h-3 rounded-full bg-green-500/80" />
          </div>
          <span className="text-white/80 text-xs font-medium ml-2">Finder</span>
          <div className="flex-1" />
          <span className="text-white/60 text-[11px]">Fri Jan 30 2:45 PM</span>
        </div>

        {/* Desktop content area */}
        <div className="flex h-full">
          {/* Floating components on left edge */}
          <div className="w-56 p-3 flex flex-col gap-2">
            {componentsOrder.map(name => componentMap[name])}
          </div>

          {/* Main desktop */}
          <div className="flex-1 p-8">
            <div className="grid grid-cols-5 gap-4">
              {[
                { icon: '📁', name: 'Projects' },
                { icon: '📄', name: 'Notes.txt' },
                { icon: '🖼️', name: 'Photo.png' },
                { icon: '📦', name: 'Archive.zip' },
                { icon: '💾', name: 'Backup' },
                { icon: '🎵', name: 'Music' },
                { icon: '🎬', name: 'Videos' },
                { icon: '📊', name: 'Data.csv' },
              ].map((item, i) => (
                <div 
                  key={i}
                  className="flex flex-col items-center gap-1 p-3 rounded-xl hover:bg-white/10 cursor-pointer transition-all hover:scale-105"
                  draggable
                >
                  <span className="text-4xl drop-shadow-lg">{item.icon}</span>
                  <span className="text-white/80 text-xs font-medium">{item.name}</span>
                </div>
              ))}
            </div>
            
            {/* Fake window */}
            <div 
              className="mt-8 rounded-xl overflow-hidden"
              style={{
                background: 'linear-gradient(135deg, rgba(255,255,255,0.1) 0%, rgba(255,255,255,0.05) 100%)',
                backdropFilter: 'blur(20px)',
                border: '1px solid rgba(255,255,255,0.15)',
                boxShadow: '0 8px 32px rgba(0,0,0,0.3)',
              }}
            >
              <div className="h-8 bg-white/5 flex items-center px-3 gap-2 border-b border-white/10">
                <div className="flex gap-1.5">
                  <div className="w-2.5 h-2.5 rounded-full bg-red-500/60" />
                  <div className="w-2.5 h-2.5 rounded-full bg-yellow-500/60" />
                  <div className="w-2.5 h-2.5 rounded-full bg-green-500/60" />
                </div>
                <span className="text-white/60 text-xs ml-2">Downloads</span>
              </div>
              <div className="p-4 text-white/40 text-sm">
                <p>Try hovering over each floating component on the left.</p>
                <p className="mt-2">Notice how the hovered one expands while others shrink back.</p>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Feature callouts */}
      <div className="relative z-10 p-6 grid grid-cols-4 gap-4">
        {[
          { title: 'Glassmorphism', desc: 'Native Tahoe-style blur and transparency' },
          { title: 'Hover Magnification', desc: 'Components expand on focus, others recede' },
          { title: 'Floating Panels', desc: 'No container—just glass floating over content' },
          { title: 'Space Efficient', desc: 'Each panel only takes space when you need it' },
        ].map((item, i) => (
          <div key={i} className="bg-white/5 backdrop-blur rounded-xl p-4 border border-white/10">
            <h3 className="text-white font-medium text-sm mb-1">{item.title}</h3>
            <p className="text-white/50 text-xs">{item.desc}</p>
          </div>
        ))}
      </div>
    </div>
  );
};

export default GlassComponents;
