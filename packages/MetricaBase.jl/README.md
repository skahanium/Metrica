# MetricaBase.jl

Protocol kernel for the Metrica ecosystem.

## Responsibilities

- Abstract model and result types
- Shared public APIs such as `fit`, `coef`, `vcov`, `predict`
- Structured result semantics such as `glance`, `tidy`, and `augment`
- ModelFrame and preprocessing contracts
- Capability and warning protocols

## Non-Responsibilities

- OLS or other estimator implementations
- Robust covariance algorithms
- Rendering tables or HTML output
- Visualization or desktop logic
