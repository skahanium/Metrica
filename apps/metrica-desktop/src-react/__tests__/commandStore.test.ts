import { describe, it, expect, beforeEach } from 'vitest';
import { useCommandStore } from '../stores/commandStore';

describe('commandStore', () => {
  beforeEach(() => {
    useCommandStore.setState({
      input: '',
      cursorPos: 0,
      context: null,
      completions: [],
      selectedCompletionIdx: 0,
      ghostText: null,
      showCompletions: false,
      correction: null,
      history: [],
      historyIdx: -1,
      lastParsed: null,
      parseError: null,
    });
  });

  describe('setInput', () => {
    it('updates input and cursor', () => {
      useCommandStore.getState().setInput('regress y', 9);
      expect(useCommandStore.getState().input).toBe('regress y');
      expect(useCommandStore.getState().cursorPos).toBe(9);
    });

    it('clears correction', () => {
      useCommandStore.setState({ correction: 'test' });
      useCommandStore.getState().setInput('x', 1);
      expect(useCommandStore.getState().correction).toBeNull();
    });
  });

  describe('completions', () => {
    it('shows completions when non-empty', () => {
      const items = [{ text: 'regress', label: 'regress', description: '', kind: 'verb' as const, priority: 5 }];
      useCommandStore.getState().setCompletions(items, { kind: 'verb' });
      expect(useCommandStore.getState().showCompletions).toBe(true);
      expect(useCommandStore.getState().selectedCompletionIdx).toBe(0);
    });

    it('hides completions when empty', () => {
      useCommandStore.getState().setCompletions([], { kind: 'verb' });
      expect(useCommandStore.getState().showCompletions).toBe(false);
    });

    it('acceptCompletion returns selected item and hides', () => {
      const items = [
        { text: 'a', label: 'a', description: '', kind: 'verb' as const, priority: 5 },
        { text: 'b', label: 'b', description: '', kind: 'verb' as const, priority: 5 },
      ];
      useCommandStore.setState({ completions: items, selectedCompletionIdx: 1, showCompletions: true });
      const item = useCommandStore.getState().acceptCompletion();
      expect(item?.text).toBe('b');
      expect(useCommandStore.getState().showCompletions).toBe(false);
    });

    it('selectNext/Prev cycle through completions', () => {
      const items = [
        { text: 'a', label: 'a', description: '', kind: 'verb' as const, priority: 5 },
        { text: 'b', label: 'b', description: '', kind: 'verb' as const, priority: 5 },
      ];
      useCommandStore.setState({ completions: items, selectedCompletionIdx: 0 });
      useCommandStore.getState().selectNextCompletion();
      expect(useCommandStore.getState().selectedCompletionIdx).toBe(1);
      useCommandStore.getState().selectNextCompletion();
      expect(useCommandStore.getState().selectedCompletionIdx).toBe(0);
      useCommandStore.getState().selectPrevCompletion();
      expect(useCommandStore.getState().selectedCompletionIdx).toBe(1);
    });

    it('hideCompletions clears correction', () => {
      useCommandStore.setState({ correction: 'fixme' });
      useCommandStore.getState().hideCompletions();
      expect(useCommandStore.getState().correction).toBeNull();
    });
  });

  describe('history', () => {
    it('adds to history and resets idx', () => {
      useCommandStore.getState().addToHistory('regress y x');
      useCommandStore.getState().addToHistory('summarize y');
      const h = useCommandStore.getState().history;
      expect(h).toEqual(['summarize y', 'regress y x']);
      expect(useCommandStore.getState().historyIdx).toBe(-1);
    });

    it('caps history at 100', () => {
      for (let i = 0; i < 110; i++) {
        useCommandStore.getState().addToHistory(`cmd ${i}`);
      }
      expect(useCommandStore.getState().history.length).toBe(100);
    });

    it('navigates history up and down', () => {
      useCommandStore.getState().addToHistory('cmd1');
      useCommandStore.getState().addToHistory('cmd2');

      const up1 = useCommandStore.getState().navigateHistoryUp();
      expect(up1).toBe('cmd2');

      const up2 = useCommandStore.getState().navigateHistoryUp();
      expect(up2).toBe('cmd1');

      // At end of history
      const up3 = useCommandStore.getState().navigateHistoryUp();
      expect(up3).toBeNull();

      const down1 = useCommandStore.getState().navigateHistoryDown();
      expect(down1).toBe('cmd2');

      const down2 = useCommandStore.getState().navigateHistoryDown();
      expect(down2).toBe('');
    });
  });

  describe('clearInput', () => {
    it('resets all input state', () => {
      useCommandStore.setState({
        input: 'test',
        ghostText: 'ing',
        showCompletions: true,
        correction: 'fix',
        completions: [{ text: 'test', label: 'test', description: '', kind: 'verb' as const, priority: 5 }],
        lastParsed: { verb: 'regress', positionals: ['y'], options: [] },
        parseError: null,
      });
      useCommandStore.getState().clearInput();
      const s = useCommandStore.getState();
      expect(s.input).toBe('');
      expect(s.ghostText).toBeNull();
      expect(s.showCompletions).toBe(false);
      expect(s.correction).toBeNull();
      expect(s.completions).toEqual([]);
    });
  });

  describe('lastParsed', () => {
    it('stores parsed result', () => {
      const parsed = { verb: 'regress', positionals: ['y', 'x'], options: [] };
      useCommandStore.getState().setLastParsed(parsed, null);
      expect(useCommandStore.getState().lastParsed).toEqual(parsed);
      expect(useCommandStore.getState().parseError).toBeNull();
    });

    it('stores parse error', () => {
      useCommandStore.getState().setLastParsed(null, 'bad command');
      expect(useCommandStore.getState().parseError).toBe('bad command');
    });
  });
});
