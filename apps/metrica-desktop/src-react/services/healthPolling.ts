import { checkHealth } from './runtimeClient';
import { useAppStore, MAX_RESTARTS } from '../stores/appStore';

const HEALTH_STARTUP_POLL_INTERVAL_MS = 1_000;  // 启动时 1 秒轮询
const HEALTH_NORMAL_POLL_INTERVAL_MS = 30_000;   // 就绪后 30 秒轮询

let pollingId: ReturnType<typeof setInterval> | null = null;
let isJuliaReady = false;

export function startHealthPolling(): void {
  if (pollingId !== null) return;

  const poll = async () => {
    try {
      const health = await checkHealth();
      useAppStore.getState().setJuliaHealth(health.julia_healthy, health.restart_count);
      
      // 检测到就绪后，切换到正常轮询间隔
      if (health.julia_healthy && !isJuliaReady) {
        isJuliaReady = true;
        if (pollingId !== null) {
          clearInterval(pollingId);
        }
        pollingId = setInterval(poll, HEALTH_NORMAL_POLL_INTERVAL_MS);
        useAppStore.getState().setHealthPollingId(pollingId);
      }
    } catch {
      useAppStore.getState().setJuliaHealth(false, useAppStore.getState().restartCount);
    }
  };

  poll();

  // 启动时使用 1 秒轮询间隔
  pollingId = setInterval(poll, HEALTH_STARTUP_POLL_INTERVAL_MS);
  useAppStore.getState().setHealthPollingId(pollingId);
}

export function stopHealthPolling(): void {
  if (pollingId !== null) {
    clearInterval(pollingId);
    pollingId = null;
    isJuliaReady = false;
    useAppStore.getState().setHealthPollingId(null);
  }
}

export { MAX_RESTARTS };
