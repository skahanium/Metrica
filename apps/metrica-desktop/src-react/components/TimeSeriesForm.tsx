import React from 'react';
import { Form, Select, InputNumber, Switch, Card } from 'antd';

interface TimeSeriesFormProps {
  modelType: 'arima' | 'var' | 'unitroot' | 'cointegration';
  columns: string[];
  onChange: (values: Record<string, unknown>) => void;
}

export const TimeSeriesForm: React.FC<TimeSeriesFormProps> = ({
  modelType,
  columns,
  onChange
}) => {
  const [form] = Form.useForm();

  const handleValuesChange = (_: Record<string, unknown>, allValues: Record<string, unknown>) => {
    onChange(allValues);
  };

  return (
    <Card title={`${modelType.toUpperCase()} 模型配置`} size="small">
      <Form
        form={form}
        layout="vertical"
        onValuesChange={handleValuesChange}
        initialValues={{
          order: [1, 1, 1],
          seasonal_order: [0, 0, 0, 0],
          include_constant: true,
          method: 'mle',
          lags: 1,
          deterministic: 'constant'
        }}
      >
        <Form.Item
          label="时间列"
          name="timeColumn"
          rules={[{ required: true, message: '请选择时间列' }]}
        >
          <Select
            placeholder="选择时间列"
            options={columns.map(c => ({ label: c, value: c }))}
          />
        </Form.Item>

        {modelType === 'arima' && (
          <>
            <Form.Item
              label="目标变量"
              name="variable"
              rules={[{ required: true, message: '请选择目标变量' }]}
            >
              <Select
                placeholder="选择目标变量"
                options={columns.map(c => ({ label: c, value: c }))}
              />
            </Form.Item>

            <Form.Item label="AR 阶数 (p)">
              <Form.Item name={['order', 0]} noStyle>
                <InputNumber min={0} max={10} style={{ width: '100%' }} />
              </Form.Item>
            </Form.Item>

            <Form.Item label="差分阶数 (d)">
              <Form.Item name={['order', 1]} noStyle>
                <InputNumber min={0} max={3} style={{ width: '100%' }} />
              </Form.Item>
            </Form.Item>

            <Form.Item label="MA 阶数 (q)">
              <Form.Item name={['order', 2]} noStyle>
                <InputNumber min={0} max={10} style={{ width: '100%' }} />
              </Form.Item>
            </Form.Item>

            <Form.Item label="估计方法" name="method">
              <Select options={[
                { label: 'MLE (最大似然)', value: 'mle' },
                { label: 'CSS (条件平方和)', value: 'css' }
              ]} />
            </Form.Item>

            <Form.Item label="包含常数项" name="includeConstant" valuePropName="checked">
              <Switch />
            </Form.Item>
          </>
        )}

        {modelType === 'var' && (
          <>
            <Form.Item
              label="变量"
              name="variables"
              rules={[{ required: true, message: '请选择变量' }]}
            >
              <Select
                mode="multiple"
                placeholder="选择变量（至少2个）"
                options={columns.map(c => ({ label: c, value: c }))}
              />
            </Form.Item>

            <Form.Item
              label="滞后阶数"
              name="lags"
              rules={[{ required: true, message: '请输入滞后阶数' }]}
            >
              <InputNumber min={1} max={10} style={{ width: '100%' }} />
            </Form.Item>

            <Form.Item label="包含常数项" name="includeConstant" valuePropName="checked">
              <Switch />
            </Form.Item>
          </>
        )}

        {modelType === 'unitroot' && (
          <>
            <Form.Item
              label="检验变量"
              name="variable"
              rules={[{ required: true, message: '请选择检验变量' }]}
            >
              <Select
                placeholder="选择检验变量"
                options={columns.map(c => ({ label: c, value: c }))}
              />
            </Form.Item>

            <Form.Item label="确定性成分" name="deterministic">
              <Select options={[
                { label: '常数项 (Constant)', value: 'constant' },
                { label: '趋势项 (Trend)', value: 'trend' },
                { label: '无 (None)', value: 'none' }
              ]} />
            </Form.Item>
          </>
        )}

        {modelType === 'cointegration' && (
          <>
            <Form.Item
              label="协整变量"
              name="variables"
              rules={[{ required: true, message: '请选择变量（至少2个）' }]}
            >
              <Select
                mode="multiple"
                placeholder="选择变量（至少2个）"
                options={columns.map(c => ({ label: c, value: c }))}
              />
            </Form.Item>

            <Form.Item label="检验方法" name="method">
              <Select options={[
                { label: 'Engle-Granger', value: 'engle_granger' },
                { label: 'Johansen', value: 'johansen' }
              ]} />
            </Form.Item>

            <Form.Item label="滞后阶数" name="lags">
              <InputNumber min={1} max={10} style={{ width: '100%' }} />
            </Form.Item>
          </>
        )}
      </Form>
    </Card>
  );
};

export default TimeSeriesForm;
