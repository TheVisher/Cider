import React, { useState } from 'react';

const CiderLogoConcepts = () => {
  const [darkMode, setDarkMode] = useState(true);
  
  const bg = darkMode ? 'bg-slate-900' : 'bg-gray-100';
  const cardBg = darkMode ? 'bg-slate-800/50' : 'bg-white';
  const text = darkMode ? 'text-white' : 'text-gray-900';
  const subtext = darkMode ? 'text-white/60' : 'text-gray-500';
  const border = darkMode ? 'border-white/10' : 'border-gray-200';

  return (
    <div className={`min-h-screen ${bg} p-8 transition-colors`}>
      {/* Header */}
      <div className="flex items-center justify-between mb-12">
        <div>
          <h1 className={`text-3xl font-bold ${text}`}>Cider Logo Concepts</h1>
          <p className={`${subtext} mt-1`}>macOS shell replacement</p>
        </div>
        <button
          className={`px-4 py-2 rounded-lg ${cardBg} ${text} border ${border}`}
          onClick={() => setDarkMode(!darkMode)}
        >
          {darkMode ? '☀️ Light' : '🌙 Dark'}
        </button>
      </div>

      {/* Logo Grid */}
      <div className="grid grid-cols-3 gap-8 mb-12">
        
        {/* Concept 1: Minimal Apple Slice / Sidebar */}
        <div className={`${cardBg} rounded-2xl p-8 border ${border}`}>
          <div className="text-center mb-6">
            <span className="text-xs font-medium text-amber-500 bg-amber-500/10 px-2 py-1 rounded-full">CONCEPT 1</span>
          </div>
          <div className="flex justify-center mb-6">
            <svg width="80" height="80" viewBox="0 0 80 80" fill="none">
              {/* Apple slice that also looks like a sidebar */}
              <rect x="8" y="8" width="20" height="64" rx="6" fill="url(#amber1)" />
              <circle cx="50" cy="40" r="28" stroke="url(#amber1)" strokeWidth="4" strokeDasharray="120 60" strokeLinecap="round" />
              <path d="M50 16 Q54 8 50 4" stroke={darkMode ? '#fff' : '#333'} strokeWidth="3" strokeLinecap="round" fill="none" opacity="0.6" />
              <defs>
                <linearGradient id="amber1" x1="0" y1="0" x2="80" y2="80">
                  <stop offset="0%" stopColor="#f59e0b" />
                  <stop offset="100%" stopColor="#d97706" />
                </linearGradient>
              </defs>
            </svg>
          </div>
          <div className="text-center">
            <div className={`text-xl font-semibold ${text} tracking-tight`}>cider</div>
            <p className={`text-xs ${subtext} mt-2`}>Sidebar + Apple slice hybrid</p>
          </div>
        </div>

        {/* Concept 2: Glass with sidebar levels */}
        <div className={`${cardBg} rounded-2xl p-8 border ${border}`}>
          <div className="text-center mb-6">
            <span className="text-xs font-medium text-amber-500 bg-amber-500/10 px-2 py-1 rounded-full">CONCEPT 2</span>
          </div>
          <div className="flex justify-center mb-6">
            <svg width="80" height="80" viewBox="0 0 80 80" fill="none">
              {/* Glass shape with liquid levels representing components */}
              <path 
                d="M20 12 L16 68 Q16 72 20 72 L60 72 Q64 72 64 68 L60 12 Z" 
                stroke="url(#amber2)" 
                strokeWidth="3" 
                fill="none"
                strokeLinejoin="round"
              />
              {/* Liquid levels - like sidebar components */}
              <rect x="22" y="54" width="36" height="14" rx="2" fill="#f59e0b" opacity="0.9" />
              <rect x="23" y="38" width="34" height="12" rx="2" fill="#f59e0b" opacity="0.7" />
              <rect x="24" y="24" width="32" height="10" rx="2" fill="#f59e0b" opacity="0.5" />
              <rect x="25" y="14" width="30" height="6" rx="2" fill="#f59e0b" opacity="0.3" />
              <defs>
                <linearGradient id="amber2" x1="20" y1="0" x2="60" y2="80">
                  <stop offset="0%" stopColor="#fbbf24" />
                  <stop offset="100%" stopColor="#d97706" />
                </linearGradient>
              </defs>
            </svg>
          </div>
          <div className="text-center">
            <div className={`text-xl font-semibold ${text} tracking-tight`}>cider</div>
            <p className={`text-xs ${subtext} mt-2`}>Glass with component "levels"</p>
          </div>
        </div>

        {/* Concept 3: Abstract C / Sidebar */}
        <div className={`${cardBg} rounded-2xl p-8 border ${border}`}>
          <div className="text-center mb-6">
            <span className="text-xs font-medium text-amber-500 bg-amber-500/10 px-2 py-1 rounded-full">CONCEPT 3</span>
          </div>
          <div className="flex justify-center mb-6">
            <svg width="80" height="80" viewBox="0 0 80 80" fill="none">
              {/* C shape that doubles as sidebar indicator */}
              <path 
                d="M56 16 Q24 16 24 40 Q24 64 56 64" 
                stroke="url(#amber3)" 
                strokeWidth="12" 
                strokeLinecap="round"
                fill="none"
              />
              {/* Small components inside the C */}
              <rect x="32" y="28" width="16" height="4" rx="2" fill={darkMode ? '#fff' : '#333'} opacity="0.5" />
              <rect x="32" y="38" width="16" height="4" rx="2" fill={darkMode ? '#fff' : '#333'} opacity="0.5" />
              <rect x="32" y="48" width="16" height="4" rx="2" fill={darkMode ? '#fff' : '#333'} opacity="0.5" />
              <defs>
                <linearGradient id="amber3" x1="24" y1="16" x2="56" y2="64">
                  <stop offset="0%" stopColor="#fcd34d" />
                  <stop offset="100%" stopColor="#f59e0b" />
                </linearGradient>
              </defs>
            </svg>
          </div>
          <div className="text-center">
            <div className={`text-xl font-semibold ${text} tracking-tight`}>cider</div>
            <p className={`text-xs ${subtext} mt-2`}>Abstract "C" with components</p>
          </div>
        </div>

        {/* Concept 4: Minimal vertical bar with apple bite */}
        <div className={`${cardBg} rounded-2xl p-8 border ${border}`}>
          <div className="text-center mb-6">
            <span className="text-xs font-medium text-amber-500 bg-amber-500/10 px-2 py-1 rounded-full">CONCEPT 4</span>
          </div>
          <div className="flex justify-center mb-6">
            <svg width="80" height="80" viewBox="0 0 80 80" fill="none">
              {/* Vertical bar with bite taken out */}
              <path 
                d="M28 8 L28 72 Q28 76 32 76 L48 76 Q52 76 52 72 L52 52 Q44 44 52 36 L52 8 Q52 4 48 4 L32 4 Q28 4 28 8 Z" 
                fill="url(#amber4)"
              />
              {/* Leaf/stem */}
              <path d="M52 4 Q58 -2 64 4" stroke="#22c55e" strokeWidth="3" strokeLinecap="round" fill="none" />
              <defs>
                <linearGradient id="amber4" x1="28" y1="0" x2="52" y2="80">
                  <stop offset="0%" stopColor="#fbbf24" />
                  <stop offset="100%" stopColor="#ea580c" />
                </linearGradient>
              </defs>
            </svg>
          </div>
          <div className="text-center">
            <div className={`text-xl font-semibold ${text} tracking-tight`}>cider</div>
            <p className={`text-xs ${subtext} mt-2`}>Sidebar bar with "bite"</p>
          </div>
        </div>

        {/* Concept 5: Squircle grid - like the app components */}
        <div className={`${cardBg} rounded-2xl p-8 border ${border}`}>
          <div className="text-center mb-6">
            <span className="text-xs font-medium text-amber-500 bg-amber-500/10 px-2 py-1 rounded-full">CONCEPT 5</span>
          </div>
          <div className="flex justify-center mb-6">
            <svg width="80" height="80" viewBox="0 0 80 80" fill="none">
              {/* Vertical stack of rounded squares - like sidebar components */}
              <rect x="20" y="4" width="40" height="16" rx="5" fill="#fcd34d" />
              <rect x="20" y="24" width="40" height="16" rx="5" fill="#fbbf24" />
              <rect x="20" y="44" width="40" height="16" rx="5" fill="#f59e0b" />
              <rect x="20" y="64" width="40" height="12" rx="5" fill="#d97706" />
            </svg>
          </div>
          <div className="text-center">
            <div className={`text-xl font-semibold ${text} tracking-tight`}>cider</div>
            <p className={`text-xs ${subtext} mt-2`}>Stacked components (literal)</p>
          </div>
        </div>

        {/* Concept 6: Minimalist - just the wordmark */}
        <div className={`${cardBg} rounded-2xl p-8 border ${border}`}>
          <div className="text-center mb-6">
            <span className="text-xs font-medium text-amber-500 bg-amber-500/10 px-2 py-1 rounded-full">CONCEPT 6</span>
          </div>
          <div className="flex justify-center items-center h-20 mb-6">
            <span 
              className="text-4xl font-bold tracking-tight"
              style={{
                background: 'linear-gradient(135deg, #fcd34d 0%, #f59e0b 50%, #ea580c 100%)',
                WebkitBackgroundClip: 'text',
                WebkitTextFillColor: 'transparent',
              }}
            >
              cider
            </span>
          </div>
          <div className="text-center">
            <div className={`text-xl font-semibold ${text} tracking-tight opacity-0`}>cider</div>
            <p className={`text-xs ${subtext} mt-2`}>Pure wordmark, gradient</p>
          </div>
        </div>
      </div>

      {/* App Icon Versions */}
      <h2 className={`text-xl font-semibold ${text} mb-6`}>App Icon Versions</h2>
      <div className="grid grid-cols-6 gap-6 mb-12">
        {/* Icon 1 */}
        <div className={`${cardBg} rounded-2xl p-6 border ${border} flex flex-col items-center`}>
          <div 
            className="w-16 h-16 rounded-2xl flex items-center justify-center mb-3"
            style={{ background: 'linear-gradient(135deg, #fcd34d 0%, #ea580c 100%)' }}
          >
            <svg width="36" height="36" viewBox="0 0 80 80" fill="none">
              <rect x="8" y="8" width="20" height="64" rx="6" fill="white" opacity="0.9" />
              <circle cx="50" cy="40" r="24" stroke="white" strokeWidth="4" strokeDasharray="100 50" strokeLinecap="round" opacity="0.9" />
            </svg>
          </div>
          <span className={`text-xs ${subtext}`}>#1</span>
        </div>

        {/* Icon 2 */}
        <div className={`${cardBg} rounded-2xl p-6 border ${border} flex flex-col items-center`}>
          <div 
            className="w-16 h-16 rounded-2xl flex items-center justify-center mb-3"
            style={{ background: 'linear-gradient(135deg, #fbbf24 0%, #dc2626 100%)' }}
          >
            <svg width="32" height="32" viewBox="0 0 80 80" fill="none">
              <path 
                d="M20 12 L16 68 Q16 72 20 72 L60 72 Q64 72 64 68 L60 12 Z" 
                stroke="white" 
                strokeWidth="3" 
                fill="none"
                opacity="0.4"
              />
              <rect x="22" y="50" width="36" height="18" rx="3" fill="white" opacity="0.9" />
              <rect x="23" y="32" width="34" height="14" rx="3" fill="white" opacity="0.7" />
              <rect x="24" y="18" width="32" height="10" rx="3" fill="white" opacity="0.5" />
            </svg>
          </div>
          <span className={`text-xs ${subtext}`}>#2</span>
        </div>

        {/* Icon 3 */}
        <div className={`${cardBg} rounded-2xl p-6 border ${border} flex flex-col items-center`}>
          <div 
            className="w-16 h-16 rounded-2xl flex items-center justify-center mb-3"
            style={{ background: 'linear-gradient(135deg, #fcd34d 0%, #f59e0b 100%)' }}
          >
            <svg width="36" height="36" viewBox="0 0 80 80" fill="none">
              <path 
                d="M56 16 Q24 16 24 40 Q24 64 56 64" 
                stroke="white" 
                strokeWidth="10" 
                strokeLinecap="round"
                fill="none"
              />
            </svg>
          </div>
          <span className={`text-xs ${subtext}`}>#3</span>
        </div>

        {/* Icon 4 */}
        <div className={`${cardBg} rounded-2xl p-6 border ${border} flex flex-col items-center`}>
          <div 
            className="w-16 h-16 rounded-2xl flex items-center justify-center mb-3"
            style={{ background: 'linear-gradient(180deg, #fcd34d 0%, #ea580c 100%)' }}
          >
            <svg width="28" height="40" viewBox="0 0 28 44" fill="none">
              <path 
                d="M4 4 L4 40 Q4 42 6 42 L22 42 Q24 42 24 40 L24 28 Q18 22 24 16 L24 4 Q24 2 22 2 L6 2 Q4 2 4 4 Z" 
                fill="white"
                opacity="0.95"
              />
              <path d="M24 2 Q28 -1 32 2" stroke="#22c55e" strokeWidth="2.5" strokeLinecap="round" fill="none" />
            </svg>
          </div>
          <span className={`text-xs ${subtext}`}>#4</span>
        </div>

        {/* Icon 5 */}
        <div className={`${cardBg} rounded-2xl p-6 border ${border} flex flex-col items-center`}>
          <div 
            className="w-16 h-16 rounded-2xl flex items-center justify-center mb-3"
            style={{ background: 'linear-gradient(135deg, #78350f 0%, #451a03 100%)' }}
          >
            <svg width="32" height="40" viewBox="0 0 40 50" fill="none">
              <rect x="4" y="2" width="32" height="10" rx="3" fill="#fcd34d" />
              <rect x="4" y="14" width="32" height="10" rx="3" fill="#fbbf24" />
              <rect x="4" y="26" width="32" height="10" rx="3" fill="#f59e0b" />
              <rect x="4" y="38" width="32" height="10" rx="3" fill="#d97706" />
            </svg>
          </div>
          <span className={`text-xs ${subtext}`}>#5</span>
        </div>

        {/* Icon 6 - Monogram */}
        <div className={`${cardBg} rounded-2xl p-6 border ${border} flex flex-col items-center`}>
          <div 
            className="w-16 h-16 rounded-2xl flex items-center justify-center mb-3 text-white text-3xl font-bold"
            style={{ background: 'linear-gradient(135deg, #f59e0b 0%, #dc2626 100%)' }}
          >
            C
          </div>
          <span className={`text-xs ${subtext}`}>#6</span>
        </div>
      </div>

      {/* Color Palette */}
      <h2 className={`text-xl font-semibold ${text} mb-6`}>Color Palette</h2>
      <div className="flex gap-4 mb-12">
        {[
          { color: '#fcd34d', name: 'Cider Light', hex: '#fcd34d' },
          { color: '#fbbf24', name: 'Cider Gold', hex: '#fbbf24' },
          { color: '#f59e0b', name: 'Cider Amber', hex: '#f59e0b' },
          { color: '#d97706', name: 'Cider Dark', hex: '#d97706' },
          { color: '#ea580c', name: 'Cider Burnt', hex: '#ea580c' },
          { color: '#78350f', name: 'Cider Brown', hex: '#78350f' },
        ].map((c, i) => (
          <div key={i} className="flex-1">
            <div 
              className="h-20 rounded-xl mb-2" 
              style={{ background: c.color }}
            />
            <div className={`text-sm ${text}`}>{c.name}</div>
            <div className={`text-xs ${subtext}`}>{c.hex}</div>
          </div>
        ))}
      </div>

      {/* Wordmark Options */}
      <h2 className={`text-xl font-semibold ${text} mb-6`}>Wordmark Options</h2>
      <div className={`${cardBg} rounded-2xl p-8 border ${border} flex justify-around items-center`}>
        <div className="text-center">
          <div className={`text-4xl font-light tracking-wide ${text}`}>cider</div>
          <div className={`text-xs ${subtext} mt-2`}>Light</div>
        </div>
        <div className="text-center">
          <div className={`text-4xl font-normal tracking-tight ${text}`}>cider</div>
          <div className={`text-xs ${subtext} mt-2`}>Regular</div>
        </div>
        <div className="text-center">
          <div className={`text-4xl font-semibold tracking-tight ${text}`}>cider</div>
          <div className={`text-xs ${subtext} mt-2`}>Semibold</div>
        </div>
        <div className="text-center">
          <div className={`text-4xl font-bold tracking-tight ${text}`}>Cider</div>
          <div className={`text-xs ${subtext} mt-2`}>Bold + Cap</div>
        </div>
        <div className="text-center">
          <div 
            className="text-4xl font-bold tracking-tight"
            style={{
              background: 'linear-gradient(135deg, #fcd34d 0%, #f59e0b 50%, #ea580c 100%)',
              WebkitBackgroundClip: 'text',
              WebkitTextFillColor: 'transparent',
            }}
          >
            cider
          </div>
          <div className={`text-xs ${subtext} mt-2`}>Gradient</div>
        </div>
      </div>

      {/* Footer note */}
      <div className={`mt-8 text-center ${subtext} text-sm`}>
        Toggle dark/light mode to see how logos work on different backgrounds
      </div>
    </div>
  );
};

export default CiderLogoConcepts;
