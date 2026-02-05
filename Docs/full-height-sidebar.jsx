import React, { useState } from 'react';

const FloatingSidebar = () => {
  const [hoveredComponent, setHoveredComponent] = useState(null);
  const [launcherPosition, setLauncherPosition] = useState('top');
  const [stagedFiles, setStagedFiles] = useState([
    { name: 'report.pdf', icon: '📄' },
    { name: 'screenshot.png', icon: '🖼️' },
    { name: 'design-v2.fig', icon: '🎨' },
  ]);
  const [expandedApps, setExpandedApps] = useState(['Finder', 'Safari']);
  const [clipboardHistory, setClipboardHistory] = useState([
    { type: 'text', content: 'https://github.com/example/repo', time: '2m ago' },
    { type: 'image', content: 'Screenshot', time: '5m ago' },
    { type: 'text', content: 'npm install sidebar-app', time: '12m ago' },
    { type: 'text', content: 'const sidebar = new Sidebar()', time: '18m ago' },
  ]);
  const [showExtensionPanel, setShowExtensionPanel] = useState(false);

  const pinnedApps = [
    { name: 'Finder', icon: '📁', color: '#4A90D9' },
    { name: 'Safari', icon: '🧭', color: '#5AC8FA' },
    { name: 'VS Code', icon: '💻', color: '#007ACC' },
    { name: 'Terminal', icon: '⬛', color: '#1a1a1a' },
    { name: 'Messages', icon: '💬', color: '#34C759' },
    { name: 'Slack', icon: '💜', color: '#611f69' },
  ];

  const openApps = [
    { name: 'Finder', icon: '📁', windows: ['Downloads', 'Documents', 'Applications'] },
    { name: 'Safari', icon: '🧭', windows: ['GitHub - repo', 'Stack Overflow', 'Apple Developer', 'MDN Web Docs'] },
    { name: 'VS Code', icon: '💻', windows: ['sidebar-app', 'pawkit-v2'] },
    { name: 'Figma', icon: '🎨', windows: ['Sidebar Design v2'] },
    { name: 'Terminal', icon: '⬛', windows: ['zsh - main', 'node server'] },
  ];

  // Example extensions that could be built
  const sampleExtensions = [
    { id: 'music', name: 'Now Playing', icon: '🎵', installed: true },
    { id: 'weather', name: 'Weather', icon: '🌤️', installed: true },
    { id: 'pomodoro', name: 'Pomodoro Timer', icon: '🍅', installed: false },
    { id: 'git', name: 'Git Status', icon: '📊', installed: false },
    { id: 'calendar', name: 'Calendar', icon: '📅', installed: false },
    { id: 'notes', name: 'Quick Notes', icon: '📝', installed: false },
  ];

  const toggleAppExpand = (appName) => {
    setExpandedApps(prev => 
      prev.includes(appName) 
        ? prev.filter(a => a !== appName)
        : [...prev, appName]
    );
  };

  // Flex-based sizing - hovered gets more, others get less, but all stay visible
  const getFlexValue = (componentName, isCore = true) => {
    if (!hoveredComponent) return isCore ? 1 : 0.6; // Default: equal distribution
    if (hoveredComponent === componentName) return 2.5; // Expanded
    return 0.5; // Contracted but still visible
  };

  const getOpacity = (componentName) => {
    if (!hoveredComponent) return 1;
    if (hoveredComponent === componentName) return 1;
    return 0.7;
  };

  // Glass component wrapper
  const GlassPanel = ({ children, name, className = '', flex = 1 }) => {
    const flexValue = getFlexValue(name);
    const opacity = getOpacity(name);
    
    return (
      <div
        className={`relative overflow-hidden transition-all duration-300 ease-out ${className}`}
        style={{
          flex: flexValue,
          minHeight: '60px',
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
          opacity,
        }}
        onMouseEnter={() => setHoveredComponent(name)}
        onMouseLeave={() => setHoveredComponent(null)}
      >
        <div 
          className="absolute inset-0 pointer-events-none"
          style={{
            background: 'radial-gradient(ellipse at top, rgba(255,255,255,0.1) 0%, transparent 60%)',
          }}
        />
        <div className="relative z-10 h-full flex flex-col">
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

  const LaunchersComponent = () => {
    const isHovered = hoveredComponent === 'launchers';
    return (
      <GlassPanel name="launchers" className="p-3">
        <div className="text-[10px] text-white/40 font-medium mb-2 px-1">PINNED APPS</div>
        <div className={`flex gap-2 flex-wrap ${isHovered ? 'justify-start' : 'justify-center'}`}>
          {pinnedApps.map((app, i) => (
            <div key={i} className={`${isHovered ? 'flex items-center gap-2 w-full p-1 rounded-lg hover:bg-white/10' : ''}`}>
              <Squircle app={app} size={isHovered ? 32 : 38} />
              {isHovered && <span className="text-xs text-white/80">{app.name}</span>}
            </div>
          ))}
        </div>
        {isHovered && (
          <div className="mt-auto pt-2 border-t border-white/10">
            <div className="text-[10px] text-white/40 text-center">Drag to reorder • Right-click for options</div>
          </div>
        )}
      </GlassPanel>
    );
  };

  const WindowsComponent = () => {
    const isHovered = hoveredComponent === 'windows';
    
    return (
      <GlassPanel name="windows" className="p-2">
        <div className="text-[10px] text-white/40 font-medium mb-2 px-1">WINDOWS</div>
        <div className="overflow-y-auto flex-1">
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
                {app.windows.length > 1 && (
                  <span className="text-white/40 text-[10px]">
                    {expandedApps.includes(app.name) ? '▼' : '▶'}
                  </span>
                )}
              </div>
              {expandedApps.includes(app.name) && app.windows.map((win, j) => (
                <div 
                  key={j}
                  className="flex items-center gap-2 py-1.5 px-2 ml-5 rounded hover:bg-white/10 cursor-pointer text-[11px] text-white/60 transition-colors group"
                >
                  <span className="w-1.5 h-1.5 rounded-full bg-white/30" />
                  <span className="truncate flex-1">{win}</span>
                  <div className="opacity-0 group-hover:opacity-100 flex gap-1 transition-opacity">
                    <button className="text-white/40 hover:text-white/80 text-[10px]" title="Minimize">─</button>
                    <button className="text-white/40 hover:text-white/80 text-[10px]" title="Close">✕</button>
                  </div>
                </div>
              ))}
            </div>
          ))}
        </div>
        {isHovered && (
          <div className="mt-2 pt-2 border-t border-white/10 flex gap-1 justify-center">
            <button className="text-[10px] text-white/50 hover:text-white/80 px-2 py-1 rounded hover:bg-white/10 transition-colors">
              + Group
            </button>
            <button className="text-[10px] text-white/50 hover:text-white/80 px-2 py-1 rounded hover:bg-white/10 transition-colors">
              Tile All
            </button>
            <button className="text-[10px] text-white/50 hover:text-white/80 px-2 py-1 rounded hover:bg-white/10 transition-colors">
              Minimize All
            </button>
          </div>
        )}
      </GlassPanel>
    );
  };

  const ClipboardComponent = () => {
    const isHovered = hoveredComponent === 'clipboard';
    
    return (
      <GlassPanel name="clipboard" className="p-2">
        <div className="text-[10px] text-white/40 font-medium mb-2 px-1">CLIPBOARD</div>
        <div className="space-y-1 overflow-y-auto flex-1">
          {clipboardHistory.slice(0, isHovered ? 10 : 3).map((item, i) => (
            <div 
              key={i}
              className={`flex items-center gap-2 p-2 rounded-lg cursor-pointer transition-colors ${
                i === 0 ? 'bg-white/15 ring-1 ring-white/20' : 'hover:bg-white/10'
              }`}
            >
              <span className="text-sm">{item.type === 'text' ? '📋' : '🖼️'}</span>
              <span className="text-xs text-white/80 flex-1 truncate">{item.content}</span>
              <span className="text-[10px] text-white/30">{item.time}</span>
            </div>
          ))}
        </div>
        {isHovered && (
          <div className="mt-2 pt-2 border-t border-white/10 flex justify-between items-center">
            <span className="text-[10px] text-white/40">{clipboardHistory.length} items</span>
            <button className="text-[10px] text-white/50 hover:text-white/80 transition-colors">
              Clear History
            </button>
          </div>
        )}
      </GlassPanel>
    );
  };

  const DropZoneComponent = () => {
    const [isDragOver, setIsDragOver] = useState(false);
    const isHovered = hoveredComponent === 'dropzone';
    
    return (
      <GlassPanel name="dropzone" className="p-2">
        <div className="flex items-center justify-between mb-2 px-1">
          <span className="text-[10px] text-white/40 font-medium">DROP ZONE</span>
          {stagedFiles.length > 0 && (
            <button 
              className="text-[10px] text-red-400/70 hover:text-red-400 transition-colors"
              onClick={() => setStagedFiles([])}
            >
              Clear
            </button>
          )}
        </div>
        <div 
          className={`border border-dashed rounded-lg p-2 transition-all flex-1 overflow-y-auto ${
            isDragOver 
              ? 'border-blue-400 bg-blue-500/20' 
              : 'border-white/20 hover:border-white/30'
          }`}
          onDragOver={(e) => { e.preventDefault(); setIsDragOver(true); }}
          onDragLeave={() => setIsDragOver(false)}
          onDrop={() => setIsDragOver(false)}
        >
          {stagedFiles.length === 0 ? (
            <div className="text-center text-white/40 text-[11px] py-4">
              <div className="text-2xl mb-2">📥</div>
              Drop files here to stage
            </div>
          ) : (
            <div className="space-y-1">
              {stagedFiles.map((file, i) => (
                <div 
                  key={i}
                  className="flex items-center gap-2 p-2 bg-white/10 rounded-lg text-xs group cursor-grab active:cursor-grabbing hover:bg-white/15 transition-colors"
                  draggable
                >
                  <span className="text-base">{file.icon}</span>
                  <span className="flex-1 truncate text-white/80">{file.name}</span>
                  <button 
                    className="text-white/30 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-all"
                    onClick={() => setStagedFiles(prev => prev.filter((_, idx) => idx !== i))}
                  >
                    ✕
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>
        {isHovered && stagedFiles.length > 0 && (
          <div className="mt-2 text-[10px] text-white/40 text-center">
            Drag files out to any app or folder
          </div>
        )}
      </GlassPanel>
    );
  };

  // Example extension components
  const MusicExtension = () => {
    const isHovered = hoveredComponent === 'music';
    return (
      <GlassPanel name="music" className="p-2">
        <div className="text-[10px] text-white/40 font-medium mb-2 px-1">NOW PLAYING</div>
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-lg bg-gradient-to-br from-pink-500 to-purple-600 flex items-center justify-center text-lg">
            🎵
          </div>
          <div className="flex-1 min-w-0">
            <div className="text-xs text-white/90 font-medium truncate">Bohemian Rhapsody</div>
            <div className="text-[10px] text-white/50 truncate">Queen</div>
          </div>
        </div>
        {isHovered && (
          <div className="mt-3 flex items-center justify-center gap-4">
            <button className="text-white/60 hover:text-white transition-colors">⏮</button>
            <button className="text-white hover:scale-110 transition-transform text-xl">▶</button>
            <button className="text-white/60 hover:text-white transition-colors">⏭</button>
          </div>
        )}
      </GlassPanel>
    );
  };

  const WeatherExtension = () => {
    const isHovered = hoveredComponent === 'weather';
    return (
      <GlassPanel name="weather" className="p-2">
        <div className="text-[10px] text-white/40 font-medium mb-2 px-1">WEATHER</div>
        <div className="flex items-center gap-3">
          <div className="text-3xl">🌤️</div>
          <div>
            <div className="text-xl text-white font-light">72°F</div>
            <div className="text-[10px] text-white/50">San Francisco</div>
          </div>
        </div>
        {isHovered && (
          <div className="mt-2 pt-2 border-t border-white/10 flex justify-between text-[10px] text-white/50">
            <span>H: 76°</span>
            <span>L: 58°</span>
            <span>💧 45%</span>
          </div>
        )}
      </GlassPanel>
    );
  };

  // Extension manager panel
  const ExtensionPanel = () => (
    <div 
      className="absolute right-4 top-20 w-72 rounded-2xl overflow-hidden z-30"
      style={{
        background: 'linear-gradient(135deg, rgba(30,30,30,0.95) 0%, rgba(20,20,20,0.98) 100%)',
        backdropFilter: 'blur(40px)',
        border: '1px solid rgba(255,255,255,0.1)',
        boxShadow: '0 20px 60px rgba(0,0,0,0.5)',
      }}
    >
      <div className="p-4 border-b border-white/10 flex items-center justify-between">
        <h3 className="text-white font-medium">Extensions</h3>
        <button 
          className="text-white/40 hover:text-white/80 transition-colors"
          onClick={() => setShowExtensionPanel(false)}
        >
          ✕
        </button>
      </div>
      <div className="p-2 max-h-80 overflow-y-auto">
        {sampleExtensions.map((ext) => (
          <div 
            key={ext.id}
            className="flex items-center gap-3 p-3 rounded-xl hover:bg-white/5 transition-colors"
          >
            <span className="text-2xl">{ext.icon}</span>
            <div className="flex-1">
              <div className="text-sm text-white/90">{ext.name}</div>
              <div className="text-[10px] text-white/40">
                {ext.installed ? 'Installed' : 'Available'}
              </div>
            </div>
            <button 
              className={`text-xs px-3 py-1 rounded-lg transition-colors ${
                ext.installed 
                  ? 'bg-white/10 text-white/60 hover:bg-red-500/20 hover:text-red-400'
                  : 'bg-blue-500/20 text-blue-400 hover:bg-blue-500/30'
              }`}
            >
              {ext.installed ? 'Remove' : 'Install'}
            </button>
          </div>
        ))}
      </div>
      <div className="p-4 border-t border-white/10">
        <button className="w-full text-sm text-white/60 hover:text-white/80 py-2 rounded-lg hover:bg-white/5 transition-colors">
          + Create Custom Extension
        </button>
      </div>
    </div>
  );

  const coreComponents = launcherPosition === 'top' 
    ? ['launchers', 'windows', 'clipboard', 'dropzone']
    : ['windows', 'clipboard', 'dropzone', 'launchers'];

  const componentMap = {
    launchers: <LaunchersComponent key="launchers" />,
    windows: <WindowsComponent key="windows" />,
    clipboard: <ClipboardComponent key="clipboard" />,
    dropzone: <DropZoneComponent key="dropzone" />,
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-indigo-950 via-purple-900 to-slate-900 relative overflow-hidden">
      {/* Animated background blobs */}
      <div className="absolute top-20 left-20 w-96 h-96 bg-purple-500/20 rounded-full blur-3xl animate-pulse" />
      <div className="absolute bottom-20 right-20 w-80 h-80 bg-blue-500/20 rounded-full blur-3xl animate-pulse" style={{ animationDelay: '1s' }} />
      
      {/* Controls */}
      <div className="relative z-20 p-4 flex items-center gap-4">
        <h1 className="text-white text-lg font-semibold">Sidebar Concept</h1>
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
        <button
          className="px-3 py-1.5 rounded-lg text-xs font-medium bg-white/5 text-white/60 hover:bg-white/10 transition-all ml-auto"
          onClick={() => setShowExtensionPanel(!showExtensionPanel)}
        >
          🧩 Extensions
        </button>
      </div>

      {/* Desktop simulation */}
      <div className="relative mx-4 rounded-2xl overflow-hidden bg-black/20" style={{ height: 'calc(100vh - 80px)' }}>
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

        {/* Main area */}
        <div className="flex h-[calc(100%-28px)]">
          {/* Floating sidebar - full height, components fill space */}
          <div className="w-52 p-2 flex flex-col gap-2 h-full">
            {/* Core components */}
            {coreComponents.map(name => componentMap[name])}
            
            {/* Divider */}
            <div className="border-t border-white/10 my-1" />
            
            {/* Extension components */}
            <MusicExtension />
            <WeatherExtension />
          </div>

          {/* Desktop content */}
          <div className="flex-1 p-6 overflow-auto">
            <div className="grid grid-cols-6 gap-3">
              {[
                { icon: '📁', name: 'Projects' },
                { icon: '📄', name: 'Notes.txt' },
                { icon: '🖼️', name: 'Photo.png' },
                { icon: '📦', name: 'Archive.zip' },
                { icon: '💾', name: 'Backup' },
                { icon: '🎵', name: 'Music' },
                { icon: '🎬', name: 'Videos' },
                { icon: '📊', name: 'Data.csv' },
                { icon: '🔧', name: 'Settings' },
                { icon: '📚', name: 'Books' },
              ].map((item, i) => (
                <div 
                  key={i}
                  className="flex flex-col items-center gap-1 p-2 rounded-xl hover:bg-white/10 cursor-pointer transition-all hover:scale-105"
                  draggable
                >
                  <span className="text-3xl drop-shadow-lg">{item.icon}</span>
                  <span className="text-white/80 text-[11px]">{item.name}</span>
                </div>
              ))}
            </div>
            
            {/* Sample window */}
            <div 
              className="mt-6 rounded-xl overflow-hidden max-w-2xl"
              style={{
                background: 'linear-gradient(135deg, rgba(255,255,255,0.08) 0%, rgba(255,255,255,0.03) 100%)',
                backdropFilter: 'blur(20px)',
                border: '1px solid rgba(255,255,255,0.12)',
                boxShadow: '0 8px 32px rgba(0,0,0,0.3)',
              }}
            >
              <div className="h-8 bg-white/5 flex items-center px-3 gap-2 border-b border-white/10">
                <div className="flex gap-1.5">
                  <div className="w-2.5 h-2.5 rounded-full bg-red-500/60" />
                  <div className="w-2.5 h-2.5 rounded-full bg-yellow-500/60" />
                  <div className="w-2.5 h-2.5 rounded-full bg-green-500/60" />
                </div>
                <span className="text-white/60 text-xs ml-2">sidebar-app — VS Code</span>
              </div>
              <div className="p-4 font-mono text-xs">
                <div className="text-purple-400">// Extension API Example</div>
                <div className="mt-2">
                  <span className="text-blue-400">interface</span>
                  <span className="text-green-400"> SidebarExtension</span>
                  <span className="text-white/60"> {'{'}</span>
                </div>
                <div className="pl-4 text-white/80">
                  <div>id: <span className="text-yellow-400">string</span>;</div>
                  <div>name: <span className="text-yellow-400">string</span>;</div>
                  <div>icon: <span className="text-yellow-400">string</span>;</div>
                  <div>render: <span className="text-blue-400">(ctx: Context)</span> =&gt; <span className="text-yellow-400">Component</span>;</div>
                  <div>onHover?: <span className="text-blue-400">()</span> =&gt; <span className="text-yellow-400">void</span>;</div>
                  <div>onDrop?: <span className="text-blue-400">(files: File[])</span> =&gt; <span className="text-yellow-400">void</span>;</div>
                </div>
                <div className="text-white/60">{'}'}</div>
              </div>
            </div>
          </div>
        </div>

        {/* Extension panel */}
        {showExtensionPanel && <ExtensionPanel />}
      </div>
    </div>
  );
};

export default FloatingSidebar;
