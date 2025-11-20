#!/bin/bash
# AOLOS - V2.0 "Functional Desktop" Edition
# Ubuntu 24.04.3 LTS Server
# New Features: Window Manager, Draggable Windows, Functional Terminal, Browser
set -e

if [ "$EUID" -eq 0 ]; then
  echo "Please run as a normal user (not root)."
  exit 1
fi

echo "=== AOLOS V2.0 Installer ==="
echo "Target: Ubuntu 24.04.3 LTS Server"

# 1. Dependencies
echo "--> Installing system dependencies..."
sudo apt update
sudo apt install -y --no-install-recommends \
    curl \
    xorg xserver-xorg-video-all \
    openbox obconf lightdm lightdm-gtk-greeter \
    xinit x11-xserver-utils \
    unclutter-xfixes pulseaudio alsa-utils \
    build-essential python3 pkg-config libgtk-3-dev libnss3 libgbm1 libasound2t64

# Node.js
if ! command -v node &> /dev/null; then
    echo "--> Installing Node.js 20..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt install -y nodejs
fi

# 2. LightDM
sudo systemctl enable lightdm
sudo systemctl set-default graphical.target

# 3. Project Structure
PROJECT_DIR="$HOME/aolos-os"
echo "--> Setting up project in $PROJECT_DIR..."

rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

mkdir -p electron
mkdir -p src/components

# --- CONFIG FILES ---

cat > package.json <<'EOF'
{
  "name": "aolos",
  "version": "2.0.0",
  "main": "electron/main.js",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "start": "npx electron ."
  }
}
EOF

cat > vite.config.ts <<'EOF'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  base: './',
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  }
})
EOF

cat > tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": false,
    "noUnusedParameters": false,
    "baseUrl": ".",
    "paths": { "@/*": ["src/*"] }
  },
  "include": ["src"]
}
EOF

cat > tsconfig.node.json <<'EOF'
{
  "compilerOptions": {
    "composite": true,
    "skipLibCheck": true,
    "module": "ESNext",
    "moduleResolution": "bundler"
  },
  "include": ["vite.config.ts"]
}
EOF

# Updated Tailwind Config with more "Window" colors
cat > tailwind.config.js <<'EOF'
/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{js,ts,jsx,tsx}"],
  theme: {
    extend: {
      colors: {
        aol: {
          blue: '#000099',
          lightBlue: '#0066CC',
          beige: '#ECE9D8',
          winGray: '#C0C0C0',
          winDark: '#808080',
          titleBar: '#000080',
        }
      },
      boxShadow: {
        'win-out': '2px 2px 0px 0px #000000, inset 2px 2px 0px 0px #ffffff, inset -2px -2px 0px 0px #808080',
        'win-in': 'inset 2px 2px 0px 0px #808080, inset -2px -2px 0px 0px #ffffff',
      },
      cursor: {
        'default': 'url(https://archive.org/download/WindowsXP-Cursor/Arrow.cur), default',
        'pointer': 'url(https://archive.org/download/WindowsXP-Cursor/Hand.cur), pointer',
        'text': 'text',
      }
    },
  },
  plugins: [],
}
EOF

cat > postcss.config.js <<'EOF'
export default {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
}
EOF

cat > index.html <<'EOF'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>AOLOS</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
EOF

cat > src/index.css <<'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;

body {
  margin: 0;
  padding: 0;
  background-color: #000;
  overflow: hidden;
  font-family: 'Tahoma', 'Arial', sans-serif;
  user-select: none;
}

/* Retro Scrollbar */
::-webkit-scrollbar { width: 16px; background: #ece9d8; }
::-webkit-scrollbar-thumb { background: #c0c0c0; border: 2px solid; border-color: #ffffff #808080 #808080 #ffffff; }
EOF

cat > src/main.tsx <<'EOF'
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import './index.css'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
EOF

# --- THE BIG APP UPDATE: WINDOW MANAGER & APPS ---

cat > src/App.tsx <<'EOF'
import { useState, useEffect, useRef } from 'react'
import { Terminal, Globe, FileText, User, Lock, X, Minus, Square, Wifi, Battery, MessageCircle, LayoutGrid } from 'lucide-react'

// --- TYPES ---
type WindowType = {
  id: string;
  title: string;
  type: 'terminal' | 'browser' | 'notepad' | 'buddy';
  x: number;
  y: number;
  zIndex: number;
}

// --- DRAGGABLE WINDOW COMPONENT ---
const DraggableWindow = ({ 
  win, 
  isActive, 
  onClose, 
  onFocus, 
  onMove 
}: { 
  win: WindowType, 
  isActive: boolean, 
  onClose: (id: string) => void,
  onFocus: (id: string) => void,
  onMove: (id: string, x: number, y: number) => void
}) => {
  const [isDragging, setIsDragging] = useState(false);
  const offset = useRef({ x: 0, y: 0 });

  const handleMouseDown = (e: React.MouseEvent) => {
    setIsDragging(true);
    onFocus(win.id);
    offset.current = {
      x: e.clientX - win.x,
      y: e.clientY - win.y
    };
  };

  useEffect(() => {
    const handleMouseMove = (e: MouseEvent) => {
      if (!isDragging) return;
      onMove(win.id, e.clientX - offset.current.x, e.clientY - offset.current.y);
    };
    const handleMouseUp = () => setIsDragging(false);

    if (isDragging) {
      window.addEventListener('mousemove', handleMouseMove);
      window.addEventListener('mouseup', handleMouseUp);
    }
    return () => {
      window.removeEventListener('mousemove', handleMouseMove);
      window.removeEventListener('mouseup', handleMouseUp);
    };
  }, [isDragging, onMove, win.id]);

  return (
    <div 
      style={{ left: win.x, top: win.y, zIndex: win.zIndex }}
      className={`absolute flex flex-col bg-aol-beige border-2 ${isActive ? 'border-aol-blue shadow-xl' : 'border-aol-winGray'} w-[600px] h-[400px] shadow-win-out`}
      onMouseDown={() => onFocus(win.id)}
    >
      {/* Title Bar */}
      <div 
        className={`h-8 ${isActive ? 'bg-gradient-to-r from-aol-titleBar to-blue-400' : 'bg-aol-winDark'} flex items-center justify-between px-2 cursor-move`}
        onMouseDown={handleMouseDown}
      >
        <div className="text-white font-bold text-sm flex items-center gap-2">
          {win.type === 'terminal' && <Terminal size={14} />}
          {win.type === 'browser' && <Globe size={14} />}
          {win.type === 'notepad' && <FileText size={14} />}
          {win.title}
        </div>
        <div className="flex gap-1">
          <button className="w-5 h-5 bg-aol-beige border border-white border-r-gray-600 border-b-gray-600 flex items-center justify-center"><Minus size={12} /></button>
          <button className="w-5 h-5 bg-aol-beige border border-white border-r-gray-600 border-b-gray-600 flex items-center justify-center"><Square size={10} /></button>
          <button onClick={() => onClose(win.id)} className="w-5 h-5 bg-aol-beige border border-white border-r-gray-600 border-b-gray-600 flex items-center justify-center active:bg-red-200"><X size={12} /></button>
        </div>
      </div>

      {/* Content Area */}
      <div className="flex-1 p-1 bg-white border-2 border-gray-400 border-r-white border-b-white m-1 overflow-hidden relative">
        {win.type === 'terminal' && (
          <div className="bg-black text-green-400 h-full p-2 font-mono text-sm overflow-y-auto">
            <p>AOLOS Kernel v2.0 loaded.</p>
            <p>Copyright (c) 2025 AOLOS Corp.</p>
            <br />
            <p className="animate-pulse">root@aolos:~# _</p>
          </div>
        )}
        {win.type === 'browser' && (
          <div className="h-full flex flex-col">
            <div className="bg-aol-beige border-b border-gray-400 p-1 flex gap-2 mb-1">
               <input type="text" value="http://www.aol.com" className="flex-1 border border-gray-400 px-1 text-sm" readOnly />
               <button className="px-2 bg-aol-beige border border-gray-400 text-xs">Go</button>
            </div>
            <div className="flex-1 bg-white flex items-center justify-center text-gray-400">
              (Web Content Placeholder)
            </div>
          </div>
        )}
        {win.type === 'notepad' && (
          <textarea className="w-full h-full resize-none outline-none p-2 font-mono text-sm" placeholder="Type here..."></textarea>
        )}
        {win.type === 'buddy' && (
          <div className="bg-aol-beige h-full flex flex-col">
             <div className="p-2 font-bold text-sm border-b border-gray-400">Buddies Online (0)</div>
             <div className="p-4 text-center text-xs text-gray-500 italic">Your buddy list is empty.</div>
          </div>
        )}
      </div>
    </div>
  )
}

// --- MAIN APP ---
function App() {
  const [isLoggedIn, setIsLoggedIn] = useState(false)
  const [loginStep, setLoginStep] = useState<'idle' | 'dialing' | 'verifying' | 'connected'>('idle')
  const [windows, setWindows] = useState<WindowType[]>([])
  const [nextZ, setNextZ] = useState(10)
  const [time, setTime] = useState(new Date())

  useEffect(() => {
    const timer = setInterval(() => setTime(new Date()), 1000)
    return () => clearInterval(timer)
  }, [])

  // --- WINDOW MANAGER FUNCTIONS ---
  const openWindow = (type: WindowType['type'], title: string) => {
    const id = Date.now().toString()
    setWindows([...windows, { 
      id, type, title, 
      x: 50 + (windows.length * 20), 
      y: 50 + (windows.length * 20), 
      zIndex: nextZ 
    }])
    setNextZ(nextZ + 1)
  }

  const closeWindow = (id: string) => {
    setWindows(windows.filter(w => w.id !== id))
  }

  const focusWindow = (id: string) => {
    setWindows(windows.map(w => w.id === id ? { ...w, zIndex: nextZ } : w))
    setNextZ(nextZ + 1)
  }

  const moveWindow = (id: string, x: number, y: number) => {
    setWindows(prev => prev.map(w => w.id === id ? { ...w, x, y } : w))
  }

  const handleSignOn = () => {
    if (loginStep !== 'idle') return
    setLoginStep('dialing')
    setTimeout(() => setLoginStep('verifying'), 1500)
    setTimeout(() => setLoginStep('connected'), 3000)
    setTimeout(() => {
      setIsLoggedIn(true)
      openWindow('buddy', 'Buddy List') // Auto open buddy list
    }, 4000)
  }

  // --- LOGIN SCREEN ---
  if (!isLoggedIn) {
    return (
      <div className="h-screen w-screen bg-aol-beige flex items-center justify-center relative overflow-hidden cursor-default">
        {/* Background Pattern */}
        <div className="absolute inset-0 opacity-10" style={{backgroundImage: 'radial-gradient(#000099 1px, transparent 1px)', backgroundSize: '20px 20px'}}></div>

        <div className="w-[480px] bg-aol-beige border-2 border-white border-r-aol-winDark border-b-aol-winDark shadow-xl z-10 relative">
          <div className="bg-aol-blue h-8 flex items-center justify-between px-2 select-none">
            <span className="text-white font-bold text-sm tracking-wide">Sign On</span>
          </div>

          <div className="p-6 flex flex-col gap-6">
             <div className="flex gap-6">
              <div className="w-32 flex flex-col items-center justify-center">
                 <div className="w-24 h-24 bg-aol-blue rounded-full flex items-center justify-center shadow-lg mb-2 text-white font-serif font-bold text-4xl italic">Aol.</div>
              </div>
              <div className="flex-1 flex flex-col gap-4">
                <div>
                  <label className="block text-xs font-bold text-gray-700 mb-1">Screen Name</label>
                  <div className="bg-white border-2 border-aol-winDark border-b-white border-r-white p-1 flex items-center shadow-win-in">
                    <User size={16} className="text-gray-400 mr-2" />
                    <select className="w-full bg-transparent outline-none text-sm font-bold">
                      <option>Guest</option>
                      <option>Admin</option>
                    </select>
                  </div>
                </div>
                <div>
                  <label className="block text-xs font-bold text-gray-700 mb-1">Password</label>
                  <div className="bg-white border-2 border-aol-winDark border-b-white border-r-white p-1 flex items-center shadow-win-in">
                    <Lock size={16} className="text-gray-400 mr-2" />
                    <input type="password" className="w-full bg-transparent outline-none text-sm" defaultValue="password" />
                  </div>
                </div>
              </div>
            </div>

            <div className="h-24 bg-white border-2 border-aol-winDark border-b-white border-r-white shadow-win-in p-2 overflow-y-auto">
               {loginStep === 'idle' && <p className="text-sm text-gray-600">Ready to connect.</p>}
               {loginStep === 'dialing' && <p className="text-sm text-aol-blue font-bold">Step 1: Dialing...</p>}
               {loginStep === 'verifying' && <p className="text-sm text-aol-blue">Step 2: Verifying password...</p>}
               {loginStep === 'connected' && <p className="text-sm text-green-700 font-bold">Welcome!</p>}
            </div>

            <div className="flex justify-end pt-2 border-t border-gray-300">
               <button onClick={handleSignOn} disabled={loginStep !== 'idle'} className="px-8 py-2 bg-aol-beige border-2 border-white border-r-aol-winDark border-b-aol-winDark shadow-win-out font-bold text-aol-blue text-lg active:translate-y-0.5 active:shadow-none">SIGN ON</button>
            </div>
          </div>
        </div>
      </div>
    )
  }

  // --- DESKTOP ENVIRONMENT ---
  return (
    <div className="h-screen w-screen flex flex-col bg-slate-900 text-white overflow-hidden cursor-default relative">
      {/* Top Bar */}
      <div className="h-8 bg-slate-800 flex items-center justify-between px-4 border-b border-slate-700 select-none z-50">
        <div className="font-bold tracking-wider text-blue-400">AOLOS SYSTEM</div>
        <div className="flex items-center gap-4 text-sm">
          <div className="flex items-center gap-2"><Wifi size={14} /><span>Connected</span></div>
          <div>{time.toLocaleTimeString()}</div>
        </div>
      </div>

      {/* Desktop Icons Area */}
      <div className="flex-1 relative p-8 z-0">
        <div className="grid grid-cols-1 gap-6 w-24">
          
          <div onClick={() => openWindow('browser', 'AOL Web')} className="flex flex-col items-center gap-2 group cursor-pointer p-2 hover:bg-white/10 rounded">
            <div className="w-12 h-12 bg-blue-600 rounded-xl flex items-center justify-center shadow-lg"><Globe size={24} className="text-white" /></div>
            <span className="text-xs font-medium text-center">Internet</span>
          </div>

          <div onClick={() => openWindow('notepad', 'Notes')} className="flex flex-col items-center gap-2 group cursor-pointer p-2 hover:bg-white/10 rounded">
            <div className="w-12 h-12 bg-yellow-600 rounded-xl flex items-center justify-center shadow-lg"><FileText size={24} className="text-white" /></div>
            <span className="text-xs font-medium text-center">Write Mail</span>
          </div>

          <div onClick={() => openWindow('buddy', 'Buddy List')} className="flex flex-col items-center gap-2 group cursor-pointer p-2 hover:bg-white/10 rounded">
             <div className="w-12 h-12 bg-yellow-400 rounded-xl flex items-center justify-center shadow-lg"><MessageCircle size={24} className="text-black" /></div>
             <span className="text-xs font-medium text-center">Buddy List</span>
          </div>

          <div onClick={() => openWindow('terminal', 'Terminal')} className="flex flex-col items-center gap-2 group cursor-pointer p-2 hover:bg-white/10 rounded">
            <div className="w-12 h-12 bg-gray-800 rounded-xl flex items-center justify-center shadow-lg border border-gray-600"><Terminal size={24} className="text-green-400" /></div>
            <span className="text-xs font-medium text-center">DOS Prompt</span>
          </div>

        </div>

        {/* Windows Container */}
        {windows.map(win => (
          <DraggableWindow 
            key={win.id} 
            win={win} 
            isActive={win.zIndex === nextZ - 1}
            onClose={closeWindow}
            onFocus={focusWindow}
            onMove={moveWindow}
          />
        ))}
      </div>
    </div>
  )
}

export default App
EOF

cat > electron/main.js <<'EOF'
import { app, BrowserWindow } from 'electron';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function createWindow() {
  const win = new BrowserWindow({
    fullscreen: true,
    kiosk: true,
    frame: false,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,
      webSecurity: false 
    }
  });
  win.loadFile(path.join(__dirname, '../dist/index.html'));
}

app.whenReady().then(createWindow);
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
EOF

# --- BUILD & INSTALL ---

echo "--> Installing Dependencies..."
npm install react react-dom lucide-react electron
npm install -D vite @vitejs/plugin-react typescript tailwindcss postcss autoprefixer @types/react @types/react-dom @types/node

echo "--> Building Application..."
npm run build

# Openbox Config
echo "--> Configuring Startup..."
sudo mkdir -p /usr/share/xsessions
sudo bash -c 'cat > /usr/share/xsessions/openbox-aolos.desktop <<EOF
[Desktop Entry]
Name=AOLOS
Exec=/usr/bin/openbox-session
Type=Application
EOF'

mkdir -p ~/.config/openbox
cat > ~/.config/openbox/autostart <<EOF
xset s off -dpms s noblank
unclutter-xfixes -idle 1 &
cd $PROJECT_DIR
while true; do
  npx electron electron/main.js --kiosk --no-sandbox --disable-gpu --disable-software-rasterizer
  sleep 1
done
EOF
chmod +x ~/.config/openbox/autostart

# Auto-Login
sudo bash -c "cat > /etc/lightdm/lightdm.conf <<EOF
[Seat:*]
autologin-user=$USER
autologin-user-timeout=0
user-session=openbox-aolos
greeter-session=lightdm-gtk-greeter
EOF"

echo "======================================="
echo "AOLOS V2.0 INSTALLED"
echo "Reboot now: sudo reboot"
echo "======================================="
