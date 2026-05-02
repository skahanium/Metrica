import { AllCommunityModule, ModuleRegistry } from 'ag-grid-community';

// Vitest 设置文件：补齐 jsdom 不提供的浏览器能力。
// Ant Design 的响应式布局会读取 window.matchMedia。
Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: (query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addListener: () => {},
    removeListener: () => {},
    addEventListener: () => {},
    removeEventListener: () => {},
    dispatchEvent: () => false,
  }),
});

ModuleRegistry.registerModules([AllCommunityModule]);
