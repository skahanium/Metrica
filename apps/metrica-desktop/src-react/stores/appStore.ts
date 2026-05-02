import { create } from 'zustand';

interface AppState {
  activeTab: string;
  isLoading: boolean;
  error: string | null;
  setActiveTab: (tab: string) => void;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
}

export const useAppStore = create<AppState>((set) => ({
  activeTab: 'glance',
  isLoading: false,
  error: null,
  setActiveTab: (activeTab) => set({ activeTab }),
  setLoading: (isLoading) => set({ isLoading }),
  setError: (error) => set({ error }),
}));
