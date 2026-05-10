import React from 'react';
import { Modal, Timeline, Typography, Button, Space, Tag } from 'antd';
import { RollbackOutlined } from '@ant-design/icons';
import { useDatasetStore } from '../stores/datasetStore';
import { useAppStore } from '../stores/appStore';

const { Text } = Typography;

const OP_LABELS: Record<string, string> = {
  filter: '筛选',
  generate: '生成变量',
  replace: '替换',
  rename: '重命名',
  drop: '删除变量',
  keep: '保留变量',
  sort: '排序',
  merge: '合并',
  reshape_long: '重塑(长)',
  reshape_wide: '重塑(宽)',
  collapse: '聚合',
  impute_missing: '缺失插补',
};

export const DataHistoryPanel: React.FC = () => {
  const dataHistoryVisible = useAppStore((s) => s.dataHistoryVisible);
  const setDataHistoryVisible = useAppStore((s) => s.setDataHistoryVisible);
  const { dataHistory, currentHistoryIndex, restoreToHistoryIndex } = useDatasetStore();

  const handleRestore = (index: number) => {
    restoreToHistoryIndex(index);
    setDataHistoryVisible(false);
  };

  return (
    <Modal
      title="数据历史"
      open={dataHistoryVisible}
      onCancel={() => setDataHistoryVisible(false)}
      width={700}
      footer={null}
    >
      {dataHistory.length === 0 ? (
        <Text type="secondary">暂无数据变换历史。</Text>
      ) : (
        <Timeline
          items={dataHistory.map((node, index) => ({
            color: index === currentHistoryIndex ? 'blue' : index < currentHistoryIndex ? 'green' : 'gray',
            children: (
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                <div>
                  <Space>
                    <Tag color={index === currentHistoryIndex ? 'blue' : 'default'}>
                      {OP_LABELS[node.op_type] || node.op_type}
                    </Tag>
                    {index === currentHistoryIndex && <Tag color="blue">当前</Tag>}
                  </Space>
                  <div style={{ marginTop: 4 }}>
                    <Text type="secondary" style={{ fontSize: 11 }}>
                      {node.row_count_before} → {node.row_count_after} 行,
                      {node.col_count_before} → {node.col_count_after} 列
                    </Text>
                  </div>
                  {node.notes.length > 0 && (
                    <div style={{ marginTop: 4 }}>
                      {node.notes.map((note, i) => (
                        <Text key={i} style={{ fontSize: 12, display: 'block' }}>{note}</Text>
                      ))}
                    </div>
                  )}
                  <Text type="secondary" style={{ fontSize: 11, display: 'block', marginTop: 4 }}>
                    {new Date(node.created_at).toLocaleString()}
                  </Text>
                </div>
                {index !== currentHistoryIndex && (
                  <Button
                    size="small"
                    icon={<RollbackOutlined />}
                    onClick={() => handleRestore(index)}
                  >
                    恢复
                  </Button>
                )}
              </div>
            ),
          }))}
        />
      )}
    </Modal>
  );
};
