import { create } from 'zustand';

interface AppState {
  isLoading: boolean;
  error: string | null;
  juliaHealthy: boolean;
  healthChecked: boolean;
  restartCount: number;
  healthPollingId: ReturnType<typeof setInterval> | null;
  dataFullscreen: boolean;
  trashVisible: boolean;
  dataHistoryVisible: boolean;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  setJuliaHealth: (healthy: boolean, restartCount: number) => void;
  setHealthChecked: () => void;
  setHealthPollingId: (id: ReturnType<typeof setInterval> | null) => void;
  setDataFullscreen: (v: boolean) => void;
  setTrashVisible: (v: boolean) => void;
  setDataHistoryVisible: (v: boolean) => void;
}

const MAX_RESTARTS = 3;

export const useAppStore = create<AppState>((set) => ({
  isLoading: false,
  error: null,
  juliaHealthy: false,
  healthChecked: false,
  restartCount: 0,
  healthPollingId: null,
  dataFullscreen: false,
  trashVisible: false,
  dataHistoryVisible: false,

  setLoading: (isLoading) => set({ isLoading }),
  setError: (error) => set({ error }),
  setJuliaHealth: (juliaHealthy, restartCount) => set((s) => ({
    juliaHealthy,
    restartCount,
    healthChecked: s.healthChecked || juliaHealthy,
  })),
  setHealthChecked: () => set({ healthChecked: true }),
  setHealthPollingId: (healthPollingId) => set({ healthPollingId }),
  setDataFullscreen: (dataFullscreen) => set({ dataFullscreen }),
  setTrashVisible: (trashVisible) => set({ trashVisible }),
  setDataHistoryVisible: (dataHistoryVisible) => set({ dataHistoryVisible }),
}));

export { MAX_RESTARTS };
