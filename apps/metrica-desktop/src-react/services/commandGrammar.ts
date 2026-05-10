export type NodeKind = 'verb' | 'depvar' | 'indepvar' | 'comma' | 'option' | 'option_value';

export interface SyntaxNode {
  kind: NodeKind;
  label: string;
  required: boolean;
  multiple: boolean;
  children?: Record<string, SyntaxNode>;
  values?: string[];
}

export interface CommandGrammar {
  verb: string;
  description: string;
  category: 'data' | 'model' | 'diagnostic' | 'postest' | 'project' | 'export';
  syntax: SyntaxNode[];
}

// ---- helpers ----

function optionValue(label: string, required: boolean, values?: string[]): SyntaxNode {
  return { kind: 'option_value', label, required, multiple: false, ...(values ? { values } : {}) };
}

function modelOptions(extra: Record<string, SyntaxNode> = {}): SyntaxNode {
  return {
    kind: 'option',
    label: '选项',
    required: false,
    multiple: true,
    children: {
      robust: { kind: 'option_value', label: 'robust', required: false, multiple: false, values: ['true'] },
      cluster: { kind: 'option_value', label: 'cluster', required: false, multiple: false },
      ...extra,
    },
  };
}

function makeModelGrammar(verb: string, description: string, extraOptions: Record<string, SyntaxNode> = {}): CommandGrammar {
  return {
    verb,
    description,
    category: 'model',
    syntax: [
      { kind: 'depvar', label: '因变量', required: true, multiple: false },
      { kind: 'indepvar', label: '自变量', required: true, multiple: true },
      { kind: 'comma', label: ',', required: false, multiple: false },
      modelOptions(extraOptions),
    ],
  };
}

// ---- all command grammars ----

const grammars: CommandGrammar[] = [
  // ===== Data commands =====
  {
    verb: 'use',
    description: '加载 CSV 数据集',
    category: 'data',
    syntax: [
      { kind: 'indepvar', label: '文件路径', required: true, multiple: false },
    ],
  },
  {
    verb: 'describe',
    description: '查看数据结构与类型',
    category: 'data',
    syntax: [
      { kind: 'indepvar', label: '变量', required: false, multiple: true },
    ],
  },
  {
    verb: 'browse',
    description: '浏览数据表',
    category: 'data',
    syntax: [
      { kind: 'indepvar', label: '变量', required: false, multiple: true },
    ],
  },
  {
    verb: 'summarize',
    description: '描述性统计',
    category: 'data',
    syntax: [
      { kind: 'indepvar', label: '变量', required: false, multiple: true },
    ],
  },
  {
    verb: 'tabulate',
    description: '频数分布表',
    category: 'data',
    syntax: [
      { kind: 'indepvar', label: '分类变量', required: true, multiple: false },
    ],
  },

  // ===== Data transform commands =====
  {
    verb: 'filter',
    description: '按条件筛选观测',
    category: 'data',
    syntax: [
      { kind: 'indepvar', label: '条件表达式', required: true, multiple: true },
    ],
  },
  {
    verb: 'impute_missing',
    description: '自动插补缺失值',
    category: 'data',
    syntax: [],
  },
  {
    verb: 'generate',
    description: '生成新变量',
    category: 'data',
    syntax: [
      { kind: 'indepvar', label: '表达式（newvar = expr）', required: true, multiple: true },
    ],
  },
  {
    verb: 'replace',
    description: '替换变量值',
    category: 'data',
    syntax: [
      { kind: 'indepvar', label: '变量', required: true, multiple: false },
      { kind: 'comma', label: ',', required: true, multiple: false },
      {
        kind: 'option',
        label: '选项',
        required: true,
        multiple: true,
        children: {
          value: { kind: 'option_value', label: '替换值表达式', required: true, multiple: false },
          if: { kind: 'option_value', label: '条件表达式', required: true, multiple: false },
        },
      },
    ],
  },
  {
    verb: 'drop',
    description: '删除变量',
    category: 'data',
    syntax: [
      { kind: 'indepvar', label: '变量列表', required: true, multiple: true },
    ],
  },
  {
    verb: 'keep',
    description: '保留变量',
    category: 'data',
    syntax: [
      { kind: 'indepvar', label: '变量列表', required: true, multiple: true },
    ],
  },
  {
    verb: 'rename',
    description: '重命名变量',
    category: 'data',
    syntax: [
      { kind: 'indepvar', label: '旧变量名', required: true, multiple: false },
      { kind: 'indepvar', label: '新变量名', required: true, multiple: false },
    ],
  },
  {
    verb: 'sort',
    description: '排序数据',
    category: 'data',
    syntax: [
      { kind: 'indepvar', label: '变量列表', required: true, multiple: true },
    ],
  },
  {
    verb: 'merge',
    description: '合并数据集',
    category: 'data',
    syntax: [
      { kind: 'indepvar', label: '合并文件路径', required: true, multiple: false },
      { kind: 'comma', label: ',', required: true, multiple: false },
      {
        kind: 'option',
        label: '选项',
        required: true,
        multiple: true,
        children: {
          on: { kind: 'option_value', label: '键列', required: true, multiple: false },
          how: { kind: 'option_value', label: '合并方式', required: false, multiple: false, values: ['inner', 'left', 'right', 'outer'] },
        },
      },
    ],
  },
  {
    verb: 'reshape',
    description: '数据重塑（长/宽格式转换）',
    category: 'data',
    syntax: [
      { kind: 'indepvar', label: '方向', required: true, multiple: false, values: ['long', 'wide'] },
      { kind: 'indepvar', label: '变量列表', required: true, multiple: true },
      { kind: 'comma', label: ',', required: true, multiple: false },
      {
        kind: 'option',
        label: '选项',
        required: true,
        multiple: true,
        children: {
          id: { kind: 'option_value', label: 'ID 列', required: true, multiple: false },
          time: { kind: 'option_value', label: '时间列', required: true, multiple: false },
        },
      },
    ],
  },
  {
    verb: 'collapse',
    description: '数据聚合/折叠',
    category: 'data',
    syntax: [
      { kind: 'indepvar', label: '值变量列表', required: true, multiple: true },
      { kind: 'comma', label: ',', required: true, multiple: false },
      {
        kind: 'option',
        label: '选项',
        required: false,
        multiple: true,
        children: {
          by: { kind: 'option_value', label: '分组变量', required: true, multiple: false },
          stats: { kind: 'option_value', label: '统计量', required: true, multiple: false, values: ['mean', 'sum', 'sd', 'min', 'max', 'count'] },
        },
      },
    ],
  },

  // ===== Model commands =====
  makeModelGrammar('regress', '普通最小二乘回归（OLS）', {
    noconstant: optionValue('noconstant', false, ['true']),
    weights: optionValue('weights', false),
  }),
  makeModelGrammar('ivregress', '工具变量回归（2SLS）', {
    endogenous: optionValue('endogenous', false),
    instruments: optionValue('instruments', false),
  }),
  makeModelGrammar('gls', '广义最小二乘法（GLS）', {
    weights: optionValue('weights', false),
  }),
  makeModelGrammar('xtreg', '面板数据回归', {
    id: { kind: 'option_value', label: 'id', required: true, multiple: false },
    time: { kind: 'option_value', label: 'time', required: true, multiple: false },
    method: { kind: 'option_value', label: 'method', required: true, multiple: false, values: ['fe', 're', 'fd', 'between', 'hdfe', 'cre'] },
  }),
  makeModelGrammar('xtivreg', '面板工具变量回归', {
    id: { kind: 'option_value', label: 'id', required: true, multiple: false },
    time: { kind: 'option_value', label: 'time', required: true, multiple: false },
    method: { kind: 'option_value', label: 'method', required: true, multiple: false, values: ['fe'] },
    endogenous: optionValue('endogenous', false),
    instruments: optionValue('instruments', false),
  }),
  makeModelGrammar('logit', '逻辑回归（Logit）'),
  makeModelGrammar('probit', '概率单位回归（Probit）'),
  makeModelGrammar('poisson', '泊松回归'),
  makeModelGrammar('ologit', '有序逻辑回归'),
  makeModelGrammar('mlogit', '多项逻辑回归'),
  makeModelGrammar('nbreg', '负二项回归'),
  makeModelGrammar('did', '双重差分（DID）', {
    id: { kind: 'option_value', label: 'id', required: true, multiple: false },
    time: { kind: 'option_value', label: 'time', required: true, multiple: false },
    treat: { kind: 'option_value', label: 'treat', required: true, multiple: false },
    post: { kind: 'option_value', label: 'post', required: true, multiple: false },
  }),
  makeModelGrammar('eventstudy', '事件研究法', {
    id: { kind: 'option_value', label: 'id', required: true, multiple: false },
    time: { kind: 'option_value', label: 'time', required: true, multiple: false },
    treat: { kind: 'option_value', label: 'treat', required: true, multiple: false },
    eventtime: { kind: 'option_value', label: 'eventtime', required: true, multiple: false },
  }),
  makeModelGrammar('ipw', '逆概率加权（IPW）', {
    treat: { kind: 'option_value', label: 'treat', required: true, multiple: false },
    outcome: optionValue('outcome', false),
  }),
  makeModelGrammar('psm', '倾向得分匹配（PSM）', {
    treat: { kind: 'option_value', label: 'treat', required: true, multiple: false },
    outcome: optionValue('outcome', false),
  }),
  makeModelGrammar('aipw', '增强逆概率加权（AIPW）', {
    treat: { kind: 'option_value', label: 'treat', required: true, multiple: false },
    outcome: optionValue('outcome', false),
  }),
  makeModelGrammar('arima', 'ARIMA 时间序列模型', {
    ar: optionValue('ar', false),
    i: optionValue('i', false),
    ma: optionValue('ma', false),
  }),
  makeModelGrammar('var', '向量自回归（VAR）', {
    lags: { kind: 'option_value', label: 'lags', required: true, multiple: false },
  }),
  makeModelGrammar('dfuller', '单位根检验（Dickey-Fuller）', {
    deterministic: { kind: 'option_value', label: 'deterministic', required: false, multiple: false, values: ['constant', 'trend', 'none'] },
  }),
  makeModelGrammar('coint', '协整检验'),

  // ===== SVY prefix command =====
  {
    verb: 'svy',
    description: '调查数据前缀（支持 ols / logit / probit / poisson）',
    category: 'model',
    syntax: [
      { kind: 'indepvar', label: '底层模型', required: true, multiple: false, values: ['ols', 'logit', 'probit', 'poisson'] },
      { kind: 'depvar', label: '因变量', required: true, multiple: false },
      { kind: 'indepvar', label: '自变量', required: true, multiple: true },
      { kind: 'comma', label: ',', required: false, multiple: false },
      {
        kind: 'option',
        label: '选项',
        required: false,
        multiple: true,
        children: {
          strata: { kind: 'option_value', label: 'strata', required: false, multiple: false },
          psu: { kind: 'option_value', label: 'psu', required: false, multiple: false },
          weights: { kind: 'option_value', label: 'weights', required: false, multiple: false },
        },
      },
    ],
  },

  // ===== Diagnostic commands =====
  {
    verb: 'ovtest',
    description: '模型设定检验（RESET）',
    category: 'diagnostic',
    syntax: [],
  },
  {
    verb: 'hettest',
    description: '异方差检验',
    category: 'diagnostic',
    syntax: [],
  },
  {
    verb: 'vif',
    description: '方差膨胀因子检验',
    category: 'diagnostic',
    syntax: [],
  },
  {
    verb: 'dwstat',
    description: 'Durbin-Watson 自相关检验',
    category: 'diagnostic',
    syntax: [],
  },
  {
    verb: 'bgodfrey',
    description: 'Breusch-Godfrey 自相关检验',
    category: 'diagnostic',
    syntax: [],
  },
  {
    verb: 'hausman',
    description: 'Hausman 模型选择检验',
    category: 'diagnostic',
    syntax: [],
  },

  // ===== Post-estimation commands =====
  {
    verb: 'predict',
    description: '生成预测值',
    category: 'postest',
    syntax: [
      { kind: 'indepvar', label: '新变量名', required: true, multiple: false },
      { kind: 'comma', label: ',', required: false, multiple: false },
      {
        kind: 'option',
        label: '选项',
        required: false,
        multiple: false,
        children: {
          xb: { kind: 'option_value', label: 'xb', required: false, multiple: false, values: ['true'] },
          residuals: { kind: 'option_value', label: 'residuals', required: false, multiple: false, values: ['true'] },
        },
      },
    ],
  },
  {
    verb: 'margins',
    description: '边际效应',
    category: 'postest',
    syntax: [
      { kind: 'comma', label: ',', required: false, multiple: false },
      {
        kind: 'option',
        label: '选项',
        required: false,
        multiple: false,
        children: {
          at: { kind: 'option_value', label: 'at', required: false, multiple: false, values: ['means'] },
        },
      },
    ],
  },
  {
    verb: 'test',
    description: '线性假设检验',
    category: 'postest',
    syntax: [
      { kind: 'indepvar', label: '表达式', required: true, multiple: false },
    ],
  },
  {
    verb: 'lincom',
    description: '线性组合检验',
    category: 'postest',
    syntax: [
      { kind: 'indepvar', label: '表达式', required: true, multiple: false },
    ],
  },
  {
    verb: 'estimates',
    description: '模型估计结果管理',
    category: 'postest',
    syntax: [
      { kind: 'indepvar', label: '操作', required: true, multiple: false, values: ['store', 'restore'] },
      { kind: 'indepvar', label: '名称', required: true, multiple: false },
    ],
  },

  // ===== Project commands =====
  {
    verb: 'save',
    description: '保存项目',
    category: 'project',
    syntax: [],
  },
  {
    verb: 'load',
    description: '加载项目',
    category: 'project',
    syntax: [],
  },
  {
    verb: 'runs',
    description: '列出运行记录',
    category: 'project',
    syntax: [],
  },
  {
    verb: 'rerun',
    description: '重新运行指定任务',
    category: 'project',
    syntax: [
      { kind: 'indepvar', label: '运行 ID', required: true, multiple: false },
    ],
  },

  // ===== Export commands =====
  {
    verb: 'export',
    description: '导出结果',
    category: 'export',
    syntax: [
      { kind: 'indepvar', label: '格式', required: true, multiple: false, values: ['markdown', 'csv', 'report'] },
    ],
  },
];

// ---- registry ----

export const COMMAND_GRAMMARS: Record<string, CommandGrammar> = {};
for (const g of grammars) {
  COMMAND_GRAMMARS[g.verb] = g;
}

export const COMMAND_LIST: string[] = Object.keys(COMMAND_GRAMMARS);

export function getGrammar(verb: string): CommandGrammar | undefined {
  return COMMAND_GRAMMARS[verb.toLowerCase()];
}
