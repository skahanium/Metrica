import React, { useRef, useEffect } from 'react';
import { Empty } from 'antd';
import { useModelStore } from '../stores/modelStore';
import { useAppStore } from '../stores/appStore';
import { ResultBlock } from './ResultBlock';

interface ResultFlowProps {
  onRerun: (command: string) => void;
}

export const ResultFlow: React.FC<ResultFlowProps> = ({ onRerun }) => {
  const containerRef = useRef<HTMLDivElement>(null);
  const modelHistory = useModelStore((s) => s.modelHistory);
  const teachingEnabled = useAppStore((s) => s.teachingEnabled);

  // Auto-scroll to bottom when new results appear
  useEffect(() => {
    if (containerRef.current) {
      containerRef.current.scrollTop = containerRef.current.scrollHeight;
    }
  }, [modelHistory.length]);

  if (modelHistory.length === 0) {
    return (
      <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <Empty description="尚无分析结果。在命令行输入 use 加载数据，然后输入 regress 等命令开始分析。" />
      </div>
    );
  }

  return (
    <div ref={containerRef} style={{ flex: 1, overflow: 'auto', padding: 16 }}>
      {modelHistory.map((item) =>
        item.result ? (
          <ResultBlock
            key={item.id}
            command={item.command || item.formula || item.label || ''}
            result={item.result}
            teachingEnabled={teachingEnabled}
            onRerun={onRerun}
          />
        ) : null
      )}
    </div>
  );
};
