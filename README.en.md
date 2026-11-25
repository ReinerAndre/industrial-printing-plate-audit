🌐 **Idioma / Language:** [🇧🇷 Português](README.md) | [🇺🇸 English](README.en.md)

![Oracle SQL](https://img.shields.io/badge/Oracle_SQL-F80000?style=for-the-badge&logo=oracle&logoColor=white)
![Data Engineering](https://img.shields.io/badge/Data_Engineering-0A66C2?style=for-the-badge&logo=databricks&logoColor=white)
![Manufacturing Analytics](https://img.shields.io/badge/Manufacturing_Analytics-2E7D32?style=for-the-badge&logo=prometheus&logoColor=white)

# 🏭 Automated Printing Plate Consumption Audit by Production Order

An **Oracle SQL** analytical solution designed to audit prepress consumables (flexographic printing plates) across finished goods Production Orders (POs), reconciling shop-floor consumption postings against engineering theoretical estimates and enabling automated daily exception alerts.

---

## 📌 The Business Challenge

In industrial printing and packaging operations, flexographic plates represent a high-cost consumable. Without an automated validation layer reconciling shop-floor postings against Production Order technical specifications, the operation faced three critical bottlenecks:

* **Lack of Waste Visibility:** Duplicate postings, unapproved remakes, or manual entry errors went unnoticed during Production Order closing.
* **Dimensional Misalignment:** Actual consumption posted in square centimeters ($\text{cm}^2$) was not systematically benchmarked against the actual printing cylinder circumference and substrate web width.
* **Operational Analysis Bottleneck:** Manually auditing hundreds of daily POs prevented the prepress team from taking corrective action prior to billing or batch closure.

---

## 🎯 Solution Objectives

* **Standardize Theoretical Engineering Calculations:** Compute expected consumption ($\text{cm}^2$) by combining actual cylinder circumference ($Z \times 3.175$), substrate web width, and the artwork's ink/color count.
* **Enforce Tolerance Governance:** Apply a maximum acceptable threshold of **+50% over expected consumption**, automatically classifying each PO as *"Within tolerance"* or *"Above tolerance"*.
* **Track Posting Accuracy:** Provide a side-by-side comparison (*Expected vs. Max Tolerance vs. Actual*) alongside percentage variance for continuous efficiency monitoring.
* **Enable Exception-Based Daily Alerting (D-1):** Structure high-selectivity filters to trigger automated daily emails containing strictly out-of-tolerance POs posted the previous day, eliminating operational noise.

---

## 📐 Architecture and Data Lineage

The SQL pipeline is structured around logical transformation layers using chained **Common Table Expressions (CTEs)**, ensuring strict granularity isolation prior to final reconciliation:

```mermaid
flowchart LR
    A["Transactional ERP<br/>(Postings, POs, Tech Specs)"] --> B["Extraction Layer<br/>(Modular CTEs)"]
    B --> C["Data Cleansing Layer<br/>(Regex & Safe Type Casting)"]
    C --> D["Business Rules Layer<br/>(cm² Calc & 50% Tolerance)"]
    D --> E["Consumption & Alerting<br/>(Management Report & D-1 Email)"]
```

1. **Modular Extraction (`lista_op`, `cte_cilindro`, `cte_cores`, `cte_largura_material`):** Each technical domain is pre-aggregated at its native Production Order grain prior to `JOIN` operations, preventing Cartesian products and metric inflation.
2. **Data Cleansing & Type Casting (`base_calculo`):** Dynamic attributes stored as free text (`VARCHAR2`) undergo regex sanitization prior to numeric casting.
3. **Business Rules Engine (`calculo_final`):** Performs unit conversion ($\text{mm}^2 \rightarrow \text{cm}^2$), applies the tolerance multiplier ($1.5\times$), and generates audit classification flags.

---

## 🛠️ Engineering & Technical Highlights

* **Cartesian Product Prevention:** Because a single PO maps to multiple components (inks, substrates) and machine accessories, aggregations (`SUM`, `COUNT`, `MAX`) are isolated within dedicated CTEs before joining with the finished good technical sheet.
* **Resilient Type Casting (`ORA-01722` Prevention):** Engineering parameters (substrate width and cylinder circumference) often reside in character columns prone to mixed formatting (comma decimals, thousand separators, or stray text). The pipeline leverages `REGEXP_REPLACE` paired with `NLS_NUMERIC_CHARACTERS` and `NULLIF` to guarantee production stability.
* **Process-Accurate Dimensional Modeling:** Rather than relying solely on the finished good's nominal height, the query prioritizes the **actual printing cylinder circumference** assigned to the PO, accurately reflecting the physical plate surface area required.
* **High-Selectivity Filtering:** Generating a binary audit flag (`filtro_auditoria`: `'A'` / `'D'`) allows scheduled email jobs to filter strictly for exceptions without re-evaluating complex business logic at the presentation layer.

---

## 🚀 Business Impact

* **Proactive Variance Detection:** Immediate identification of anomalous plate consumption on D+1, enabling timely posting corrections or prepress root-cause investigation.
* **Focus on Exceptions (Noise Reduction):** The prepress engineering team reviews only POs exceeding the 50% tolerance ceiling, significantly reducing daily audit overhead.
* **Reliable Accuracy Baseline:** Establishes an auditable KPI bridging product engineering specifications and shop-floor execution, strengthening industrial cost control.

---

📖 For execution instructions, parameters, and the output data dictionary, refer to the [User Guide](docs/user_guide.en.md).
