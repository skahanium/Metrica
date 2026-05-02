interface EmptyStateProps {
  title: string;
  description?: string;
}

export function EmptyState({ title, description }: EmptyStateProps) {
  return (
    <div style={{ padding: '24px', textAlign: 'center', color: '#8c8c8c' }}>
      <strong>{title}</strong>
      {description && <p style={{ marginTop: 8 }}>{description}</p>}
    </div>
  );
}
