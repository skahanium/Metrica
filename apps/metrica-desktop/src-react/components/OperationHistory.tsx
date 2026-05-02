import { Empty, List, Tag, Typography } from 'antd';
import { useTransformStore } from '../stores/transformStore';

export function OperationHistory() {
  const { history, lastTransformResult } = useTransformStore();
  const items = lastTransformResult?.status === 'error' ? [lastTransformResult] : history;

  if (!items.length) return <Empty description="暂无数据操作历史" />;

  return (
    <List
      size="small"
      dataSource={items}
      renderItem={(item, index) => (
        <List.Item>
          <List.Item.Meta
            title={<><Tag color={item.status === 'error' ? 'red' : 'green'}>{item.status}</Tag>{index + 1}. {item.operation}</>}
            description={
              item.status === 'error'
                ? <Typography.Text type="danger">第 {item.error?.op_index ?? index + 1} 步失败：{item.error?.message}</Typography.Text>
                : <span>{item.result?.notes}（{item.result?.nrows} 行 × {item.result?.ncols} 列）</span>
            }
          />
        </List.Item>
      )}
    />
  );
}
