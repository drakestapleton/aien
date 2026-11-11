# Aien

<!-- languages -->
[English](README.md) · **简体中文**
<!-- /languages -->

Aien 是 AIEN 系统旨在长期维系的持久主体：在 iMac、Raspberry Pi、DGX Spark 和 MacBook 上保持同一个身份（架构 ADR 0035）。本仓库是 Aien 的项目主页：包括使命、阶段账本（P0 至 P7），以及一份计划，涵盖数据契约、评估框架、发布清单，以及首个通过鉴定的版本 **Aien B0** 的验收契约。

Allen 现已演化为最终的 Aien（2026-10-26）。在此之前，本仓库名为 `aien-dev/allen`；GitHub 会重定向旧的 URL。

**Pre-alpha。** 这里的一切都尚未通过鉴定。本仓库中的每项主张都链接到 `evidence/` 下的某个文件，或 [aien-dev/aien-receipts](https://github.com/aien-dev/aien-receipts) 中的某个凭证；没有链接的句子是计划，而不是结果。

## 工作原理：一个已实现的评估流程

目前 `main` 上唯一的评估流程是微任务准入内核（[docs/GOAL_MICROJOBS.md](docs/GOAL_MICROJOBS.md)）。规划器和模型针对单个目标提出事件，一个种子自举的 Omega 程序（[`src/goal_microjobs/kernel.om`](src/goal_microjobs/kernel.om)）仅依据计划和日志就接纳这些事件，或以带编码的退出码拒绝它们。它不持有任何身份，也不写入任何 Cortex 记忆。**[完整示例课程](docs/TEACHING.md)** 从种子重新构建固定版本的编译器，并运行离线门禁：158 项检查通过，9 个故意损坏的内核全部被识别出来。编译器固定版本错误时，会以退出码 3 拒绝。[重放记录](docs/teaching-replay-2026-11-05.txt)。模型推理、Cortex、B0 和硬件仍为 NOT_RUN。

## 哪些内容在这里，哪些不在

| 在这里 | 不在这里（归属方） |
|---|---|
| 使命、阶段议题 P0 至 P7；B0 验收契约已在计划中 | Aien 的身份对象，SubjectState kind 24（aienos-mv，ADR 0018） |
| 对话日志清单已在计划中：数量、日期、主机、缺口 | 日志本身（Spark `~/archive/agent-chats/`，受访问控制） |
| 数据契约和合成测试夹具已在计划中 | 原始对话、训练后的权重、机密（绝不放入任何仓库） |
| 评估框架和发布清单已在计划中（摘要、固定版本） | 记忆（Cortex，ADR 0022）、运行时权限（aegis-runtime-mv、aien-sovereign-core-mv）、协议（aien-protocols-mv） |
| 项目关闭守卫和源代码控制守卫已在计划中，`main` 上尚不存在 | 模型权重和各代模型（仅按摘要记录） |

把协调工作移到这里，不会产生第二个身份，也不会分叉记忆或权限。各组件的归属方保持不变；本仓库提供指向它们的链接。

## 目录结构

- `docs/MISSION.md`：Aien 的使命和终点，以 Drake 的原话表述。
- `docs/PHASES.md`：阶段账本 P0 至 P7，附议题链接和状态。
- `docs/PLAN.md`：P0 工作流、目录、分支。
- `docs/SOURCE_MAP.md`：计划中的源码映射，含固定的提交（工作流 `map`）；不在 `main` 上。
- `inventory/`：计划中的对话日志清单和受访问控制的源清单（工作流 `inventory`）；目前只有 `.gitkeep`。
- `docs/B0_ACCEPTANCE_CONTRACT.md`：计划中的有界任务和门禁（工作流 `contract`）；不在 `main` 上。
- `guard/`：计划中的 Rust `aien-guard` 项目关闭守卫和源代码控制守卫（工作流 `guards`）；目前只有 `.gitkeep`，`main` 上没有 crate，也没有策略。
- `evidence/`：预留给测试日志和运行凭证，每个工作流一个目录；目前只有 `.gitkeep`。

## 可见性

按照议题 aien-architecture-mv#279 的要求，本仓库于 2026-10-20 以私有方式创建。`docs/PLAN.md` 曾提议，在 `main` 上的源代码控制守卫通过之后再将仓库公开。本仓库现已公开可读，但这棵 `main` 树中既没有守卫，也没有守卫通过的凭证；公开可见并不是计划中的保护措施已经运行的证据。无论可见性如何，原始日志、个人训练产物和权重都保持受访问控制。

## 许可

AGPL-3.0-or-later。AIEN 为非商业项目。

## 人类主导的智能体工程

开发遵循人类主导的智能体工程（HDAE）：由人类定义目标、架构、约束、验收标准和停止点；智能体在这些边界内负责实现、执行检查、诊断故障并进行修改。人类评审仍对主张、验收和发布决策负责。这里描述的是开发方法，并不改变运行时自主性，也不改变历史证据。

有关该方法的文档和一个系统软件案例研究，请参阅 Gregory M. Kurtzer（2026），*Ginux: Building an Independent Kernel That Runs Linux Userspace through Human-Directed Agentic Engineering*，技术报告，v1，Zenodo，<https://doi.org/10.5281/zenodo.23682548>。
