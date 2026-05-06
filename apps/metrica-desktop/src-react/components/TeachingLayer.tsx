import React, { useState } from 'react';
import { Button, Typography, Tag } from 'antd';
import type { ModelResult } from '../types/protocol';

const { Text, Paragraph } = Typography;

interface TeachingLayerProps {
  result: ModelResult;
  defaultCollapsed?: boolean;
}

export const TeachingLayer: React.FC<TeachingLayerProps> = ({ result, defaultCollapsed = false }) => {
  const [collapsed, setCollapsed] = useState(defaultCollapsed);
  const notes = (result as any).teaching_notes;
  if (!notes) return null;

  return (
    <div style={{ marginBottom: 12 }}>
      <Button type="link" size="small" onClick={() => setCollapsed(!collapsed)}
        style={{ padding: 0, fontSize: 12 }}>
        📖 {collapsed ? '显示教学解读' : '收起教学解读'}
      </Button>
      {!collapsed && (
        <div style={{ padding: '12px 16px', background: '#f6ffed', borderRadius: 8, border: '1px solid #b7eb8f', marginTop: 8 }}>
          {notes.equation && <Paragraph style={{ marginBottom: 4 }}><Text strong>{notes.equation}</Text></Paragraph>}
          {notes.interpretations?.map((item: string, i: number) => (
            <Text key={i} style={{ display: 'block', fontSize: 13, marginBottom: 2 }}>{item}</Text>
          ))}
          {notes.next_steps && (
            <div style={{ marginTop: 8 }}>
              <Text type="secondary" style={{ fontSize: 12 }}>下一步建议：</Text>
              {notes.next_steps.map((step: string, i: number) => (
                <Tag key={i} color="blue" style={{ marginTop: 2 }}>{step}</Tag>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
};
