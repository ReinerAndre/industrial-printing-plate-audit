🌐 **Idioma / Language:** [🇧🇷 Português](user_guide.md) | [🇺🇸 English](user_guide.en.md)

# 📖 Technical & Deployment Guide

This document outlines the technical prerequisites, output data dictionary, and parameterization instructions for running the **Printing Plate Consumption Audit by Production Order** query.

---

## 1. Prerequisites and Dependencies

* **Database Engine:** Oracle Database 11g or higher (requires support for chained `WITH` CTEs and `REGEXP_REPLACE`).
* **Required Privileges:** Read (`SELECT`) access on the transactional and master tables under the `erp_raw` schema, plus `EXECUTE` privilege on the scalar function `fn_busca_atributo_ficha`.
* **Expected Source Tables & Objects:**
  * `erp_raw.fato_apontamento_insumo`: Shop-floor consumable postings by Production Order.
  * `erp_raw.fato_op_acessorio`, `erp_raw.dim_acessorio`, `erp_raw.dim_ficha_acessorio`: Printing cylinder assignments and technical attributes (`tipo_acessorio = 3`, attributes `211` and `213`).
  * `erp_raw.fato_op_componente`, `erp_raw.dim_op_grupo_componente`: Ink components assigned to the Production Order.
  * `erp_raw.dim_estrutura_componente`: Bill of Materials (BOM) structure used to retrieve base substrate web width (`seq_grupo = 1`).
  * `erp_raw.dim_ficha_tecnica`, `erp_raw.dim_produto`: Finished good master data and dimensional attributes.

---

## 2. Output Data Dictionary

| Column | Data Type | Description & Business Rule |
| :--- | :--- | :--- |
| `cod_empresa` | `NUMBER` | Manufacturing plant / company identifier. |
| `data_apontamento` | `DATE` | Truncated posting date (`TRUNC`) for the plate consumption record. |
| `num_op` | `NUMBER` | Audited Production Order (PO) number. |
| `cod_produto` | `VARCHAR2` | Finished Good (FG) item code. |
| `cod_versao` | `VARCHAR2` | Engineering revision/version of the Finished Good. |
| `desc_produto` | `VARCHAR2` | Commercial/technical description of the Finished Good. |
| `material_componente` | `VARCHAR2` | Base substrate/material code (`seq_grupo = 1`) used as width reference. |
| `cod_acessorio` | `VARCHAR2` | Printing cylinder code assigned to the PO. |
| `num_z` | `VARCHAR2` | Cylinder gear tooth count ($Z$) (`atributo = 213`). |
| `circunferencia_cilindro` | `VARCHAR2` | Raw cylinder circumference value in millimeters (`atributo = 211`). |
| `altura_mm` | `NUMBER` | Sanitized cylinder circumference in millimeters (defaults to `1` if null). |
| `largura_mm` | `NUMBER` | Sanitized base substrate width in millimeters (defaults to `1` if null). |
| `n_cores` | `NUMBER` | Total count of active ink colors assigned to the PO. |
| `previsto_cm2` | `NUMBER` | Theoretical expected consumption: `ROUND(((altura_mm * largura_mm) / 100) * n_cores, 2)`. |
| `tolerancia_max_cm2` | `NUMBER` | Maximum acceptable ceiling (+50%): `ROUND(previsto_cm2 * 1.5, 2)`. |
| `realizado_cm2` | `NUMBER` | Total actual plate consumption posted ($\text{cm}^2$) for the PO and date. |
| `perc_consumo_vs_previsto` | `NUMBER` | Percentage variance between actual and expected: `((realizado - previsto) / previsto) * 100`. |
| `status_auditoria` | `VARCHAR2` | Business-friendly audit status: `'OPs acima da tolerância'` or `'OP dentro da tolerância'`. |
| `filtro_auditoria` | `CHAR(1)` | Technical filter flag: `'A'` (Above tolerance) or `'D'` (Within tolerance). |

---

## 3. Execution & Parameterization

### Input Parameters (Bind Variables)

Map the bind variables below according to your reporting tool or job scheduler:

* `:p_cod_empresa` *(Required)*: Numeric company/plant code (e.g., `6`).
* `:p_num_op` *(Optional)*: Specific Production Order number for ad-hoc inspection. Pass `NULL` to evaluate all POs within the date range.
* `:p_data_inicio` & `:p_data_fim` *(Required)*: Posting date range boundaries.
* `:p_filtro_auditoria` *(Optional)*:
  * `'A'` — Returns strictly **POs above tolerance**.
  * `'D'` — Returns strictly **POs within tolerance**.
  * `NULL` — Returns **all POs** to compute overall posting accuracy.

### Automated Daily Alerting Setup (D-1)

To schedule a daily automated email dispatch to the prepress engineering team containing strictly previous-day exceptions, configure the job parameters as follows:

```sql
-- Parameter configuration example for Daily Scheduled Job (D-1)
:p_data_inicio      := TRUNC(SYSDATE - 1);
:p_data_fim         := TRUNC(SYSDATE) - (1/86400); -- Through 23:59:59 of the previous day
:p_filtro_auditoria := 'A';                        -- Strictly POs above tolerance
```
