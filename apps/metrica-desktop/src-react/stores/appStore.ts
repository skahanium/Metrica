import { create } from 'zustand';
import { checkHealth } from '../services/runtimeClient';

interface AppState {
  isLoading: boolean;
  error: string | null;
  juliaHealthy: boolean;
  restartCount: number;
  healthPollingId: ReturnType<typeof setInterval> | null;
  dataFullscreen: boolean;
  trashVisible: boolean;
  dataHistoryVisible: boolean;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  setJuliaHealth: (healthy: boolean, restartCount: number) => void;
  startHealthPolling: () => void;
  stopHealthPolling: () => void;
  setDataFullscreen: (v: boolean) => void;
  setTrashVisible: (v: boolean) => void;
  setDataHistoryVisible: (v: boolean) => void;
}

const HEALTH_POLL_INTERVAL_MS = 30_000;
const MAX_RESTARTS = 3;

export const useAppStore = create<AppState>((set, get) => ({
  isLoading: false,
  error: null,
  juliaHealthy: true,
  restartCount: 0,
  healthPollingId: null,
  dataFullscreen: false,
  trashVisible: false,
  dataHistoryVisible: false,

  setLoading: (isLoading) => set({ isLoading }),
  setError: (error) => set({ error }),
  setJuliaHealth: (juliaHealthy, restartCount) => set({ juliaHealthy, restartCount }),
  setDataFullscreen: (dataFullscreen) => set({ dataFullscreen }),
  setTrashVisible: (trashVisible) => set({ trashVisible }),
  setDataHistoryVisible: (dataHistoryVisible) => set({ dataHistoryVisible }),

  startHealthPolling: () => {
    const { healthPollingId } = get();
    if (healthPollingId !== null) return; // 已在轮询

    const poll = async () => {
      try {
        const health = await checkHealth();
        set({
          juliaHealthy: health.julia_healthy,
          restartCount: health.restart_count,
        });
      } catch {
        set({ juliaHealthy: false });
      }
    };

    // 立即检查一次
    poll();

    const id = setInterval(poll, HEALTH_POLL_INTERVAL_MS);
    set({ healthPollingId: id });
  },

  stopHealthPolling: () => {
    const { healthPollingId } = get();
    if (healthPollingId !== null) {
      clearInterval(healthPollingId);
      set({ healthPollingId: null });
    }
  },
}));

export { MAX_RESTARTS };
