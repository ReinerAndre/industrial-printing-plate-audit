-- =============================================================================
-- PROJETO: Auditoria de Consumo de Clichês por Ordem de Produção (OP)
-- DIALETO: Oracle SQL
-- DESCRIÇÃO: Compara o consumo apontado de clichês (cm²) contra o cálculo
--            teórico de engenharia (circunferência do cilindro x largura do
--            substrato x número de cores), aplicando margem de tolerância de 50%.
-- =============================================================================

SELECT *
  FROM (
    -- 1. Consolida os apontamentos reais do insumo de clichê por OP e data
    WITH lista_op AS (
        SELECT ins.cod_empresa,
               TRUNC(ins.dt_apontamento) AS data_apontamento,
               ins.num_op,
               ins.cod_produto,
               ins.cod_versao,
               SUM(ins.qtd_apontada) AS quantidade_realizada_cm2
          FROM erp_raw.fato_apontamento_insumo ins
         WHERE ins.cod_empresa = :p_cod_empresa
           AND ins.cod_insumo = 'MAT_CLICHE_01'
           AND (:p_num_op IS NULL OR ins.num_op = :p_num_op)
           AND ins.dt_apontamento BETWEEN :p_data_inicio AND :p_data_fim
         GROUP BY ins.cod_empresa,
                  TRUNC(ins.dt_apontamento),
                  ins.num_op,
                  ins.cod_produto,
                  ins.cod_versao
    ),

    -- 2. Extrai os parâmetros técnicos do cilindro vinculado à OP (Nº de dentes Z e circunferência)
    cte_cilindro AS (
        SELECT ace.cod_empresa,
               ace.num_op,
               ace.cod_acessorio,
               MAX(CASE face.cod_atributo WHEN 213 THEN face.val_parametro END) AS num_z,
               MAX(CASE face.cod_atributo WHEN 211 THEN face.val_parametro END) AS circunferencia_cilindro
          FROM erp_raw.fato_op_acessorio ace
         INNER JOIN erp_raw.dim_acessorio mace
            ON mace.cod_empresa = ace.cod_empresa
           AND mace.cod_acessorio = ace.cod_acessorio
           AND mace.tipo_acessorio = 3 -- Tipo 3: Cilindro de impressão
         INNER JOIN erp_raw.dim_ficha_acessorio face
            ON face.cod_empresa = mace.cod_empresa
           AND face.cod_acessorio = mace.cod_acessorio
           AND face.cod_atributo IN (213, 211)
         INNER JOIN lista_op
            ON lista_op.cod_empresa = ace.cod_empresa
           AND lista_op.num_op = ace.num_op
         GROUP BY ace.cod_empresa,
                  ace.num_op,
                  ace.cod_acessorio
    ),

    -- 3. Contabiliza a quantidade de cores (tintas aplicadas) na estrutura da OP
    cte_cores AS (
        SELECT pc.cod_empresa,
               pc.num_op,
               COUNT(*) AS n_cores
          FROM erp_raw.fato_op_componente pc
         INNER JOIN erp_raw.dim_op_grupo_componente pg
            ON pg.cod_empresa = pc.cod_empresa
           AND pg.num_op = pc.num_op
           AND pg.seq_grupo = pc.seq_grupo
         INNER JOIN lista_op
            ON lista_op.cod_empresa = pc.cod_empresa
           AND lista_op.num_op = pc.num_op
         WHERE pg.desc_grupo LIKE '%TINTA%'
           AND pc.seq_aplicacao IS NOT NULL
         GROUP BY pc.cod_empresa,
                  pc.num_op
    ),

    -- 4. Obtém a largura do substrato/material base a partir da estrutura do produto
    cte_largura_material AS (
        SELECT comp.cod_empresa,
               lista_op.num_op,
               MAX(comp.cod_componente) AS material_componente,
               MAX(comp.val_largura_varchar) AS largura_raw
          FROM erp_raw.dim_estrutura_componente comp
         INNER JOIN lista_op
            ON lista_op.cod_empresa = comp.cod_empresa
           AND comp.chave_composicao = lista_op.cod_produto || '/' || lista_op.cod_versao
         WHERE comp.seq_grupo = 1 -- Grupo principal de substrato/material base
           AND comp.seq_aplicacao IS NOT NULL
         GROUP BY comp.cod_empresa,
                  lista_op.num_op
    ),

    -- 5. Consolida metadados cadastrais, ficha técnica dimensional e cruzamento com CTEs auxiliares
    base_bruta AS (
        SELECT DISTINCT
               fic.cod_empresa,
               lista_op.data_apontamento,
               lista_op.num_op,
               fic.cod_produto,
               fic.cod_versao,
               it.desc_produto,
               cil.cod_acessorio,
               cil.num_z,
               cil.circunferencia_cilindro,
               mat.material_componente,
               erp_raw.fn_busca_atributo_ficha(
                   fic.cod_empresa, fic.cod_produto, fic.cod_versao, lista_op.num_op,
                   CASE it.tipo_ficha
                       WHEN 1 THEN 601
                       WHEN 4 THEN 603
                       WHEN 5 THEN 605
                       ELSE 601
                   END
               ) AS altura_fg,
               mat.largura_raw,
               NVL(cor.n_cores, 0) AS n_cores,
               lista_op.quantidade_realizada_cm2 AS realizado_cm2
          FROM erp_raw.dim_ficha_tecnica fic
         INNER JOIN erp_raw.dim_produto it
            ON it.cod_empresa = fic.cod_empresa
           AND it.cod_produto = fic.cod_produto
         INNER JOIN lista_op
            ON lista_op.cod_empresa = fic.cod_empresa
           AND lista_op.cod_produto = fic.cod_produto
           AND lista_op.cod_versao = fic.cod_versao
          LEFT JOIN cte_cilindro cil
            ON cil.cod_empresa = lista_op.cod_empresa
           AND cil.num_op = lista_op.num_op
          LEFT JOIN cte_cores cor
            ON cor.cod_empresa = lista_op.cod_empresa
           AND cor.num_op = lista_op.num_op
          LEFT JOIN cte_largura_material mat
            ON mat.cod_empresa = lista_op.cod_empresa
           AND mat.num_op = lista_op.num_op
         WHERE fic.cod_atributo IN (600, 601, 602, 603, 604, 605)
    ),

    -- 6. Higienização e tipagem segura (VARCHAR2 -> NUMBER) contra erros de conversão (ORA-01722)
    base_calculo AS (
        SELECT bb.*,
               NVL(
                   TO_NUMBER(
                       NULLIF(
                           REGEXP_REPLACE(
                               REPLACE(
                                   CASE 
                                       WHEN INSTR(bb.circunferencia_cilindro, '.') > 0 AND INSTR(bb.circunferencia_cilindro, ',') > 0 
                                           THEN REPLACE(bb.circunferencia_cilindro, '.', '')
                                       ELSE bb.circunferencia_cilindro
                                   END,
                                   ',', '.'
                               ),
                               '[^0-9.]', ''
                           ),
                           ''
                       ),
                       '999999999999D999999',
                       'NLS_NUMERIC_CHARACTERS=''.,'''
                   ),
                   1
               ) AS altura_mm,
               NVL(
                   TO_NUMBER(
                       NULLIF(
                           REGEXP_REPLACE(
                               REPLACE(
                                   CASE 
                                       WHEN INSTR(bb.largura_raw, '.') > 0 AND INSTR(bb.largura_raw, ',') > 0 
                                           THEN REPLACE(bb.largura_raw, '.', '')
                                       ELSE bb.largura_raw
                                   END,
                                   ',', '.'
                               ),
                               '[^0-9.]', ''
                           ),
                           ''
                       ),
                       '999999999999D999999',
                       'NLS_NUMERIC_CHARACTERS=''.,'''
                   ),
                   1
               ) AS largura_mm
          FROM base_bruta bb
    ),

    -- 7. Aplicação da regra de engenharia: conversão mm² -> cm² (/100) e teto de tolerância (+50%)
    calculo_final AS (
        SELECT b.*,
               ROUND(((b.altura_mm * b.largura_mm) / 100) * b.n_cores, 2) AS previsto_cm2,
               ROUND((((b.altura_mm * b.largura_mm) / 100) * b.n_cores) * 1.5, 2) AS tolerancia_max_cm2
          FROM base_calculo b
    )

    -- 8. Projeção final com métricas de desvio percentual e flags de auditoria
    SELECT cf.cod_empresa,
           cf.data_apontamento,
           cf.num_op,
           cf.cod_produto,
           cf.cod_versao,
           cf.desc_produto,
           cf.material_componente,
           cf.cod_acessorio,
           cf.num_z,
           cf.circunferencia_cilindro,
           cf.altura_mm,
           cf.largura_mm,
           cf.n_cores,
           cf.previsto_cm2,
           cf.tolerancia_max_cm2,
           cf.realizado_cm2,
           CASE
               WHEN cf.previsto_cm2 > 0 THEN
                   ROUND(((cf.realizado_cm2 - cf.previsto_cm2) / cf.previsto_cm2) * 100, 2)
               ELSE 0
           END AS perc_consumo_vs_previsto,
           CASE
               WHEN cf.realizado_cm2 > cf.tolerancia_max_cm2 THEN 'OPs acima da tolerância'
               ELSE 'OP dentro da tolerância'
           END AS status_auditoria,
           CASE
               WHEN cf.realizado_cm2 > cf.tolerancia_max_cm2 THEN 'A'
               ELSE 'D'
           END AS filtro_auditoria
      FROM calculo_final cf
) cons
 WHERE (:p_filtro_auditoria IS NULL OR cons.filtro_auditoria = :p_filtro_auditoria);
