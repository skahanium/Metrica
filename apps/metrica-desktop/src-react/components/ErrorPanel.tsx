import { Alert } from 'antd';

interface ErrorPanelProps {
  messages: Array<{ code: string; text: string; hint?: string }>;
}

export function ErrorPanel({ messages }: ErrorPanelProps) {
  if (!messages.length) return null;
  return (
    <div style={{ marginBottom: 16 }}>
      {messages.map((m, i) => (
        <Alert
          key={i}
          type="error"
          message={m.code}
          description={m.hint ? `${m.text} ${m.hint}` : m.text}
          style={{ marginBottom: 8 }}
        />
      ))}
    </div>
  );
}
