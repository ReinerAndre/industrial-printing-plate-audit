🌐 **Idioma / Language:** [🇧🇷 Português](user_guide.md) | [🇺🇸 English](user_guide.en.md)

# 📖 Guia Técnico e de Implantação

Este documento detalha os requisitos técnicos, o dicionário de dados de saída e as instruções de parametrização para execução da consulta de **Auditoria de Consumo de Clichês por OP**.

---

## 1. Pré-requisitos e Dependências

* **Banco de Dados:** Oracle Database 11g ou superior (suporte a `WITH` / CTEs encadeadas e funções `REGEXP_REPLACE`).
* **Permissões Necessárias:** Privilégio de leitura (`SELECT`) nas tabelas transacionais e cadastrais do schema `erp_raw` e permissão de execução (`EXECUTE`) na função escalar `fn_busca_atributo_ficha`.
* **Tabelas e Objetos de Origem Esperados:**
  * `erp_raw.fato_apontamento_insumo`: Registro de consumo real de insumos por OP.
  * `erp_raw.fato_op_acessorio`, `erp_raw.dim_acessorio`, `erp_raw.dim_ficha_acessorio`: Vínculo e especificações técnicas dos cilindros (`tipo_acessorio = 3`, atributos `211` e `213`).
  * `erp_raw.fato_op_componente`, `erp_raw.dim_op_grupo_componente`: Estrutura de tintas aplicadas na OP.
  * `erp_raw.dim_estrutura_componente`: Estrutura de engenharia para obtenção da largura do substrato base (`seq_grupo = 1`).
  * `erp_raw.dim_ficha_tecnica`, `erp_raw.dim_produto`: Cadastro e atributos dimensionais do produto acabado.

---

## 2. Dicionário de Dados de Saída

| Coluna | Tipo | Descrição e Regra de Negócio |
| :--- | :--- | :--- |
| `cod_empresa` | `NUMBER` | Código identificador da unidade fabril / empresa. |
| `data_apontamento` | `DATE` | Data truncada (`TRUNC`) do apontamento de consumo do clichê. |
| `num_op` | `NUMBER` | Número da Ordem de Produção (OP) auditada. |
| `cod_produto` | `VARCHAR2` | Código do Produto Acabado (PA). |
| `cod_versao` | `VARCHAR2` | Versão de engenharia do Produto Acabado. |
| `desc_produto` | `VARCHAR2` | Descrição comercial/técnica do Produto Acabado. |
| `material_componente` | `VARCHAR2` | Código do substrato/material base (`seq_grupo = 1`) utilizado como referência de largura. |
| `cod_acessorio` | `VARCHAR2` | Código do cilindro de impressão vinculado à OP. |
| `num_z` | `VARCHAR2` | Número de dentes ($Z$) do cilindro (`atributo = 213`). |
| `circunferencia_cilindro` | `VARCHAR2` | Valor bruto da circunferência do cilindro em milímetros (`atributo = 211`). |
| `altura_mm` | `NUMBER` | Circunferência do cilindro convertida e higienizada em milímetros (fallback `1` se nulo). |
| `largura_mm` | `NUMBER` | Largura do substrato base convertida e higienizada em milímetros (fallback `1` se nulo). |
| `n_cores` | `NUMBER` | Quantidade total de tintas com aplicação ativa na OP. |
| `previsto_cm2` | `NUMBER` | Consumo teórico calculado: `ROUND(((altura_mm * largura_mm) / 100) * n_cores, 2)`. |
| `tolerancia_max_cm2` | `NUMBER` | Teto máximo aceitável (+50%): `ROUND(previsto_cm2 * 1.5, 2)`. |
| `realizado_cm2` | `NUMBER` | Soma total apontada do insumo de clichê ($\text{cm}^2$) na OP e data. |
| `perc_consumo_vs_previsto` | `NUMBER` | Variação percentual entre o realizado e o previsto: `((realizado - previsto) / previsto) * 100`. |
| `status_auditoria` | `VARCHAR2` | Rótulo gerencial: `'OPs acima da tolerância'` ou `'OP dentro da tolerância'`. |
| `filtro_auditoria` | `CHAR(1)` | Flag técnica para filtragem rápida: `'A'` (Acima da tolerância) ou `'D'` (Dentro da tolerância). |

---

## 3. Como Executar e Parametrizar

### Parâmetros de Execução (Bind Variables)

Substitua ou vincule as variáveis de entrada conforme a ferramenta de relatórios ou orquestrador utilizado:

* `:p_cod_empresa` *(Obrigatório)*: Código numérico da empresa (ex: `6`).
* `:p_num_op` *(Opcional)*: Número específico de OP para auditoria pontual. Passe `NULL` para analisar todas as OPs do período.
* `:p_data_inicio` e `:p_data_fim` *(Obrigatórios)*: Intervalo de datas de apontamento.
* `:p_filtro_auditoria` *(Opcional)*:
  * `'A'` — Retorna apenas **OPs acima da tolerância**.
  * `'D'` — Retorna apenas **OPs dentro da tolerância**.
  * `NULL` — Retorna **todas as OPs** para cálculo consolidado de acuracidade.

### Configuração para Disparo Diário Automatizado (D-1)

Para agendar o envio automático diário à equipe de pré-impressão focando apenas nas exceções do dia anterior, configure os filtros da rotina agendada com os seguintes critérios:

```sql
-- Exemplo de parametrização para Job Diário (D-1)
:p_data_inicio      := TRUNC(SYSDATE - 1);
:p_data_fim         := TRUNC(SYSDATE) - (1/86400); -- Até 23:59:59 do dia anterior
:p_filtro_auditoria := 'A';                        -- Somente OPs acima da tolerância
```
