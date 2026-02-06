# 文档索引

这里是 `sing-box-deve` 的场景化文档入口。

## 场景文档

- `docs/Serv00.md`：Serv00 单账号与批量账号部署说明
- `docs/SAP.md`：SAP Cloud Foundry 单账号与批量账号部署说明
- `docs/Docker.md`：Docker/Compose 部署说明

## 可选模板说明

- GitHub 保活工作流（`main.yml` / `mainh.yml`）是可选模板，默认部署不依赖
- Workers 保活模板（`workers_keep.js`）是可选模板，按需启用

## 规格与约束

- `docs/V1-SPEC.md`：V1 功能范围、安全策略、实现进度
- `docs/CONVENTIONS.md`：命名规则与目录约定（对齐官方风格）
- `docs/ACCEPTANCE-MATRIX.md`：验收矩阵与实机验证命令
- `docs/PANEL-TEMPLATE.md`：中英文面板输出模板
- `docs/REAL-WORLD-VALIDATION.md`：实机验收执行单（PASS/FAIL 判定）

## 推荐阅读顺序

1. 先看 `README.md` 的快速开始
2. 再看对应场景文档（Serv00/SAP/Docker）
3. 最后看 `docs/V1-SPEC.md` 了解边界和路线图
