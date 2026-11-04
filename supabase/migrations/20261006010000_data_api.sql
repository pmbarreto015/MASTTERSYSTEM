-- API de dados do MatterdiSistem.
--
-- A aplicação nunca envia SQL para o servidor. As consultas comuns chegam
-- como estruturas JSON validadas e os relatórios usam nomes fechados. Todas
-- as funções de dados são SECURITY INVOKER para que as políticas RLS sejam
-- aplicadas ao usuário autenticado.

CREATE SCHEMA IF NOT EXISTS matterdi_private;
REVOKE ALL ON SCHEMA matterdi_private FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA matterdi_private TO authenticated;

CREATE OR REPLACE FUNCTION matterdi_private.assert_table(table_name text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
BEGIN
  IF table_name IS NULL OR table_name NOT IN (
    'customers', 'products', 'insumos', 'sellers', 'suppliers',
    'employees', 'orders', 'order_items', 'financial',
    'stock_movements', 'pontos', 'holerites', 'materiais', 'maquinas',
    'retalhos', 'composicoes', 'composicao_itens', 'agenda_followups',
    'system_users'
  ) THEN
    RAISE EXCEPTION 'Tabela não permitida.' USING ERRCODE = '22023';
  END IF;
  RETURN table_name;
END;
$$;

CREATE OR REPLACE FUNCTION matterdi_private.assert_column(
  table_name text,
  column_name text
)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
BEGIN
  PERFORM matterdi_private.assert_table(table_name);
  IF column_name IS NULL
     OR column_name !~ '^[a-z][a-z0-9_]*$'
     OR NOT EXISTS (
       SELECT 1
       FROM pg_catalog.pg_attribute AS attribute
       JOIN pg_catalog.pg_class AS relation
         ON relation.oid = attribute.attrelid
       JOIN pg_catalog.pg_namespace AS namespace
         ON namespace.oid = relation.relnamespace
       WHERE namespace.nspname = 'public'
         AND relation.relname = table_name
         AND attribute.attname = column_name
         AND attribute.attnum > 0
         AND NOT attribute.attisdropped
     ) THEN
    RAISE EXCEPTION 'Coluna não permitida.' USING ERRCODE = '22023';
  END IF;
  RETURN column_name;
END;
$$;

CREATE OR REPLACE FUNCTION matterdi_private.select_columns(
  table_name text,
  columns_json jsonb
)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  column_value jsonb;
  column_name text;
  result text := '';
BEGIN
  PERFORM matterdi_private.assert_table(table_name);
  IF columns_json IS NULL OR columns_json = 'null'::jsonb THEN
    RETURN '*';
  END IF;
  IF jsonb_typeof(columns_json) <> 'array'
     OR jsonb_array_length(columns_json) = 0 THEN
    RAISE EXCEPTION 'Lista de colunas inválida.' USING ERRCODE = '22023';
  END IF;
  FOR column_value IN SELECT value FROM jsonb_array_elements(columns_json)
  LOOP
    IF jsonb_typeof(column_value) <> 'string' THEN
      RAISE EXCEPTION 'Coluna inválida.' USING ERRCODE = '22023';
    END IF;
    column_name := column_value #>> '{}';
    PERFORM matterdi_private.assert_column(table_name, column_name);
    result := result || CASE WHEN result = '' THEN '' ELSE ', ' END
      || pg_catalog.quote_ident(column_name);
  END LOOP;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION matterdi_private.write_columns(
  table_name text,
  values_json jsonb
)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  column_name text;
  result text := '';
BEGIN
  PERFORM matterdi_private.assert_table(table_name);
  IF values_json IS NULL OR jsonb_typeof(values_json) <> 'object'
     OR values_json = '{}'::jsonb THEN
    RAISE EXCEPTION 'Valores inválidos.' USING ERRCODE = '22023';
  END IF;
  FOR column_name IN
    SELECT value FROM jsonb_object_keys(values_json) AS keys(value)
  LOOP
    PERFORM matterdi_private.assert_column(table_name, column_name);
    result := result || CASE WHEN result = '' THEN '' ELSE ', ' END
      || pg_catalog.quote_ident(column_name);
  END LOOP;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION matterdi_private.compile_filters(
  table_name text,
  filters_json jsonb
)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  item jsonb;
  item_index integer := 0;
  column_name text;
  rhs_column text;
  operator_name text;
  connector text;
  scalar_value text;
  values_sql text;
  expression_sql text;
  result text := '';
BEGIN
  PERFORM matterdi_private.assert_table(table_name);
  IF filters_json IS NULL OR filters_json = 'null'::jsonb
     OR filters_json = '[]'::jsonb THEN
    RETURN '';
  END IF;
  IF jsonb_typeof(filters_json) <> 'array' THEN
    RAISE EXCEPTION 'Filtros inválidos.' USING ERRCODE = '22023';
  END IF;

  FOR item IN SELECT value FROM jsonb_array_elements(filters_json)
  LOOP
    IF jsonb_typeof(item) <> 'object' THEN
      RAISE EXCEPTION 'Filtro inválido.' USING ERRCODE = '22023';
    END IF;
    column_name := item->>'column';
    operator_name := item->>'operator';
    connector := lower(COALESCE(item->>'connector', 'and'));
    PERFORM matterdi_private.assert_column(table_name, column_name);
    IF connector NOT IN ('and', 'or') THEN
      RAISE EXCEPTION 'Conector inválido.' USING ERRCODE = '22023';
    END IF;

    IF operator_name = 'is_null' THEN
      expression_sql := pg_catalog.format('%I IS NULL', column_name);
    ELSIF operator_name = 'is_not_null' THEN
      expression_sql := pg_catalog.format('%I IS NOT NULL', column_name);
    ELSIF operator_name = 'column_lte' THEN
      rhs_column := item->>'rhs_column';
      PERFORM matterdi_private.assert_column(table_name, rhs_column);
      expression_sql := pg_catalog.format('%I <= %I', column_name, rhs_column);
    ELSIF operator_name = 'in' THEN
      IF jsonb_typeof(item->'values') <> 'array'
         OR jsonb_array_length(item->'values') = 0
         OR EXISTS (
           SELECT 1
           FROM jsonb_array_elements(item->'values') AS entries(value)
           WHERE jsonb_typeof(value) IN ('object', 'array', 'null')
         ) THEN
        RAISE EXCEPTION 'Lista de filtro inválida.' USING ERRCODE = '22023';
      END IF;
      SELECT string_agg(pg_catalog.quote_literal(value #>> '{}'), ', ')
        INTO values_sql
        FROM jsonb_array_elements(item->'values') AS entries(value);
      expression_sql := pg_catalog.format('%I IN (%s)', column_name, values_sql);
    ELSIF operator_name = 'between' THEN
      IF jsonb_typeof(item->'values') <> 'array'
         OR jsonb_array_length(item->'values') <> 2 THEN
        RAISE EXCEPTION 'Intervalo inválido.' USING ERRCODE = '22023';
      END IF;
      expression_sql := pg_catalog.format(
        '%I BETWEEN %L AND %L',
        column_name,
        item->'values'->>0,
        item->'values'->>1
      );
    ELSE
      IF item->'value' IS NULL
         OR jsonb_typeof(item->'value') IN ('object', 'array', 'null') THEN
        RAISE EXCEPTION 'Valor de filtro inválido.' USING ERRCODE = '22023';
      END IF;
      scalar_value := item->'value' #>> '{}';
      expression_sql := CASE operator_name
        WHEN 'eq' THEN pg_catalog.format('%I = %L', column_name, scalar_value)
        WHEN 'ne' THEN pg_catalog.format('%I <> %L', column_name, scalar_value)
        WHEN 'gt' THEN pg_catalog.format('%I > %L', column_name, scalar_value)
        WHEN 'gte' THEN pg_catalog.format('%I >= %L', column_name, scalar_value)
        WHEN 'lt' THEN pg_catalog.format('%I < %L', column_name, scalar_value)
        WHEN 'lte' THEN pg_catalog.format('%I <= %L', column_name, scalar_value)
        WHEN 'ilike' THEN pg_catalog.format('%I ILIKE %L', column_name, scalar_value)
        WHEN 'ieq' THEN pg_catalog.format(
          'lower(%I::text) = lower(%L)', column_name, scalar_value
        )
        WHEN 'date_eq' THEN pg_catalog.format(
          'left(%I::text, 10) = left(%L, 10)', column_name, scalar_value
        )
        ELSE NULL
      END;
      IF expression_sql IS NULL THEN
        RAISE EXCEPTION 'Operador inválido.' USING ERRCODE = '22023';
      END IF;
    END IF;

    result := result
      || CASE
           WHEN item_index = 0 THEN ''
           WHEN connector = 'or' THEN ' OR '
           ELSE ' AND '
         END
      || expression_sql;
    item_index := item_index + 1;
  END LOOP;
  RETURN CASE WHEN result = '' THEN '' ELSE ' WHERE ' || result END;
END;
$$;

CREATE OR REPLACE FUNCTION matterdi_private.compile_order(
  table_name text,
  order_json jsonb
)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  item jsonb;
  column_name text;
  expression_name text;
  direction_name text;
  expression_sql text;
  result text := '';
BEGIN
  PERFORM matterdi_private.assert_table(table_name);
  IF order_json IS NULL OR order_json = 'null'::jsonb
     OR order_json = '[]'::jsonb THEN
    RETURN '';
  END IF;
  IF jsonb_typeof(order_json) <> 'array' THEN
    RAISE EXCEPTION 'Ordenação inválida.' USING ERRCODE = '22023';
  END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(order_json)
  LOOP
    direction_name := lower(COALESCE(item->>'direction', 'asc'));
    IF direction_name NOT IN ('asc', 'desc') THEN
      RAISE EXCEPTION 'Direção de ordenação inválida.' USING ERRCODE = '22023';
    END IF;
    expression_name := item->>'expression';
    IF expression_name = 'agenda_status' THEN
      IF table_name <> 'agenda_followups' THEN
        RAISE EXCEPTION 'Ordenação não permitida.' USING ERRCODE = '22023';
      END IF;
      expression_sql := 'CASE WHEN status = ''concluido'' THEN 1 ELSE 0 END';
    ELSE
      column_name := item->>'column';
      PERFORM matterdi_private.assert_column(table_name, column_name);
      IF COALESCE((item->>'nocase')::boolean, false) THEN
        expression_sql := pg_catalog.format('lower(%I::text)', column_name);
      ELSE
        expression_sql := pg_catalog.quote_ident(column_name);
      END IF;
    END IF;
    result := result || CASE WHEN result = '' THEN '' ELSE ', ' END
      || expression_sql || ' ' || upper(direction_name);
  END LOOP;
  RETURN CASE WHEN result = '' THEN '' ELSE ' ORDER BY ' || result END;
END;
$$;

CREATE OR REPLACE FUNCTION public.matterdi_data(payload jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  operation text := payload->>'operation';
  table_name text := payload->>'table';
  values_json jsonb := payload->'values';
  columns_sql text;
  filters_sql text;
  order_sql text;
  sql_text text;
  result jsonb;
  affected integer;
  inserted_id bigint;
  query_limit integer;
  query_offset integer;
BEGIN
  IF payload IS NULL OR jsonb_typeof(payload) <> 'object' THEN
    RAISE EXCEPTION 'Operação inválida.' USING ERRCODE = '22023';
  END IF;

  IF operation = 'query' THEN
    PERFORM matterdi_private.assert_table(table_name);
    IF payload->>'group_by' IS NOT NULL OR payload->>'having' IS NOT NULL THEN
      RAISE EXCEPTION 'Agrupamento não disponível nesta consulta.' USING ERRCODE = '0A000';
    END IF;
    columns_sql := matterdi_private.select_columns(table_name, payload->'columns');
    filters_sql := matterdi_private.compile_filters(table_name, payload->'filters');
    order_sql := matterdi_private.compile_order(table_name, payload->'order');
    query_limit := COALESCE((payload->>'limit')::integer, 10000);
    query_offset := COALESCE((payload->>'offset')::integer, 0);
    IF query_limit < 1 OR query_limit > 10000 OR query_offset < 0 THEN
      RAISE EXCEPTION 'Paginação inválida.' USING ERRCODE = '22023';
    END IF;
    sql_text := pg_catalog.format(
      'SELECT COALESCE(jsonb_agg(to_jsonb(result_row)), ''[]''::jsonb) '
      'FROM (SELECT %s%s FROM public.%I%s%s LIMIT %s OFFSET %s) AS result_row',
      CASE WHEN COALESCE((payload->>'distinct')::boolean, false)
        THEN 'DISTINCT ' ELSE '' END,
      columns_sql,
      table_name,
      filters_sql,
      order_sql,
      query_limit,
      query_offset
    );
    EXECUTE sql_text INTO result;
    RETURN COALESCE(result, '[]'::jsonb);
  END IF;

  IF operation = 'insert' THEN
    columns_sql := matterdi_private.write_columns(table_name, values_json);
    sql_text := pg_catalog.format(
      'INSERT INTO public.%I (%s) '
      'SELECT %s FROM jsonb_populate_record(NULL::public.%I, $1) '
      'RETURNING id',
      table_name, columns_sql, columns_sql, table_name
    );
    EXECUTE sql_text INTO inserted_id USING values_json;
    RETURN to_jsonb(inserted_id);
  END IF;

  IF operation = 'update' THEN
    columns_sql := matterdi_private.write_columns(table_name, values_json);
    filters_sql := matterdi_private.compile_filters(table_name, payload->'filters');
    IF filters_sql = '' THEN
      RAISE EXCEPTION 'Atualização sem filtro não permitida.' USING ERRCODE = '22023';
    END IF;
    sql_text := pg_catalog.format(
      'UPDATE public.%I SET (%s) = '
      '(SELECT %s FROM jsonb_populate_record(NULL::public.%I, $1))%s',
      table_name, columns_sql, columns_sql, table_name, filters_sql
    );
    EXECUTE sql_text USING values_json;
    GET DIAGNOSTICS affected = ROW_COUNT;
    RETURN to_jsonb(affected);
  END IF;

  IF operation = 'delete' THEN
    PERFORM matterdi_private.assert_table(table_name);
    filters_sql := matterdi_private.compile_filters(table_name, payload->'filters');
    IF filters_sql = '' THEN
      RAISE EXCEPTION 'Exclusão sem filtro não permitida.' USING ERRCODE = '22023';
    END IF;
    EXECUTE pg_catalog.format('DELETE FROM public.%I%s', table_name, filters_sql);
    GET DIAGNOSTICS affected = ROW_COUNT;
    RETURN to_jsonb(affected);
  END IF;

  IF operation = 'customer_add_purchase' THEN
    UPDATE public.customers
       SET total_purchases = COALESCE(total_purchases, 0)
         + (payload->>'amount')::double precision
     WHERE id = (payload->>'id')::bigint;
    GET DIAGNOSTICS affected = ROW_COUNT;
    RETURN to_jsonb(affected);
  END IF;

  IF operation = 'seller_refresh_sales' THEN
    IF (payload->>'seller_id')::bigint <> (payload->>'target_id')::bigint THEN
      RAISE EXCEPTION 'Vendedor inválido.' USING ERRCODE = '22023';
    END IF;
    UPDATE public.sellers AS seller
       SET total_sales = COALESCE((
             SELECT SUM(sale.total)
             FROM public.orders AS sale
             WHERE sale.seller_id = (payload->>'seller_id')::bigint
               AND sale.status <> 'cancelado'
           ), 0),
           updated_at = payload->>'updated_at'
     WHERE seller.id = (payload->>'target_id')::bigint;
    GET DIAGNOSTICS affected = ROW_COUNT;
    RETURN to_jsonb(affected);
  END IF;

  RAISE EXCEPTION 'Operação não permitida.' USING ERRCODE = '22023';
END;
$$;

CREATE OR REPLACE FUNCTION public.matterdi_report(
  report_name text,
  arguments jsonb DEFAULT '[]'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  result jsonb;
BEGIN
  IF arguments IS NULL OR jsonb_typeof(arguments) <> 'array' THEN
    RAISE EXCEPTION 'Argumentos inválidos.' USING ERRCODE = '22023';
  END IF;

  CASE report_name
    WHEN 'financial_customer_summary' THEN
      SELECT jsonb_agg(to_jsonb(row_value)) INTO result FROM (
        SELECT COUNT(*) AS total_transacoes,
          SUM(CASE WHEN type = 'receber' AND is_paid = 0 THEN amount ELSE 0 END) AS total_aberto,
          SUM(CASE WHEN type = 'receber' AND is_paid = 1 THEN amount ELSE 0 END) AS total_pago,
          SUM(CASE WHEN type = 'receber' AND is_paid = 0 AND left(due_date, 10) < current_date::text THEN amount ELSE 0 END) AS total_vencido,
          SUM(CASE WHEN type = 'receber' THEN amount ELSE 0 END) AS total_comprado
        FROM public.financial WHERE customer_id = (arguments->>0)::bigint
      ) AS row_value;
    WHEN 'financial_dashboard' THEN
      SELECT jsonb_agg(to_jsonb(row_value)) INTO result FROM (
        SELECT
          SUM(CASE WHEN type = 'receber' AND is_paid = 0 THEN amount ELSE 0 END) AS a_receber,
          SUM(CASE WHEN type = 'receber' AND is_paid = 1 THEN amount ELSE 0 END) AS recebido,
          SUM(CASE WHEN type = 'pagar' AND is_paid = 0 THEN amount ELSE 0 END) AS a_pagar,
          SUM(CASE WHEN type = 'pagar' AND is_paid = 1 THEN amount ELSE 0 END) AS pago,
          COUNT(CASE WHEN type = 'receber' AND is_paid = 0 AND left(due_date, 10) < current_date::text THEN 1 END) AS vencidos_qtde,
          SUM(CASE WHEN type = 'receber' AND is_paid = 0 AND left(due_date, 10) < current_date::text THEN amount ELSE 0 END) AS vencidos_valor
        FROM public.financial
      ) AS row_value;
    WHEN 'financial_projection' THEN
      SELECT jsonb_agg(to_jsonb(row_value)) INTO result FROM (
        SELECT
          SUM(CASE WHEN type = 'receber' AND is_paid = 0 AND due_date BETWEEN arguments->>0 AND arguments->>1 THEN amount ELSE 0 END) AS a_receber_projetado,
          SUM(CASE WHEN type = 'pagar' AND is_paid = 0 AND due_date BETWEEN arguments->>2 AND arguments->>3 THEN amount ELSE 0 END) AS a_pagar_projetado
        FROM public.financial
      ) AS row_value;
    WHEN 'stock_summary' THEN
      SELECT jsonb_agg(to_jsonb(row_value)) INTO result FROM (
        SELECT COUNT(*) AS total_produtos, SUM(estoque) AS total_estoque,
          SUM(estoque * preco) AS valor_total_estoque,
          COUNT(CASE WHEN estoque <= 0 THEN 1 END) AS produtos_esgotados,
          COUNT(CASE WHEN estoque < 10 AND estoque > 0 THEN 1 END) AS produtos_baixo,
          COUNT(CASE WHEN estoque < 5 AND estoque > 0 THEN 1 END) AS produtos_criticos
        FROM public.products WHERE ativo = 1
      ) AS row_value;
    WHEN 'seller_totals' THEN
      SELECT jsonb_agg(to_jsonb(row_value)) INTO result FROM (
        SELECT COALESCE(SUM(total), 0) AS total_vendas, COUNT(id) AS total_pedidos
        FROM public.orders
        WHERE seller_id = (arguments->>0)::bigint AND status <> 'cancelado'
      ) AS row_value;
    WHEN 'seller_sales_total' THEN
      SELECT jsonb_agg(to_jsonb(row_value)) INTO result FROM (
        SELECT COALESCE(SUM(total), 0) AS total_vendas
        FROM public.orders
        WHERE seller_id = (arguments->>0)::bigint AND status <> 'cancelado'
      ) AS row_value;
    WHEN 'sales_by_seller' THEN
      SELECT COALESCE(jsonb_agg(to_jsonb(row_value)), '[]'::jsonb) INTO result FROM (
        SELECT seller.id, seller.name AS vendedor, seller.commission,
          seller.total_sales AS total_vendas,
          COALESCE(SUM(sale.total * seller.commission / 100), 0) AS total_comissao,
          COUNT(sale.id) AS quantidade_pedidos
        FROM public.sellers AS seller
        LEFT JOIN public.orders AS sale
          ON sale.seller_id = seller.id AND sale.status <> 'cancelado'
        GROUP BY seller.id ORDER BY seller.total_sales DESC
      ) AS row_value;
    WHEN 'sales_dashboard' THEN
      SELECT jsonb_agg(to_jsonb(row_value)) INTO result FROM (
        SELECT COUNT(*) AS total_vendedores,
          SUM(total_sales) AS total_vendas_geral,
          AVG(commission) AS media_comissao,
          MAX(total_sales) AS melhor_venda,
          (SELECT name FROM public.sellers ORDER BY total_sales DESC LIMIT 1) AS melhor_vendedor
        FROM public.sellers WHERE active = 1
      ) AS row_value;
    WHEN 'retalhos_count' THEN
      SELECT jsonb_build_array(jsonb_build_object('total', COUNT(*))) INTO result FROM public.retalhos;
    WHEN 'retalhos_by_status' THEN
      SELECT COALESCE(jsonb_agg(to_jsonb(row_value)), '[]'::jsonb) INTO result FROM (
        SELECT status, COUNT(*) AS total FROM public.retalhos GROUP BY status
      ) AS row_value;
    WHEN 'retalhos_available_area' THEN
      SELECT jsonb_build_array(jsonb_build_object('total', SUM(area))) INTO result
        FROM public.retalhos WHERE status = 'disponivel';
    WHEN 'retalhos_available_value' THEN
      SELECT jsonb_build_array(jsonb_build_object('total', SUM(valor_estimado))) INTO result
        FROM public.retalhos WHERE status = 'disponivel';
    WHEN 'materiais_count' THEN
      SELECT jsonb_build_array(jsonb_build_object('total', COUNT(*))) INTO result FROM public.materiais;
    WHEN 'materiais_by_category' THEN
      SELECT COALESCE(jsonb_agg(to_jsonb(row_value)), '[]'::jsonb) INTO result FROM (
        SELECT categoria, COUNT(*) AS total FROM public.materiais
        WHERE active = 1 GROUP BY categoria
      ) AS row_value;
    WHEN 'materiais_stock_value' THEN
      SELECT jsonb_build_array(jsonb_build_object('total', SUM(quantidade_estoque * preco_por_m2))) INTO result
        FROM public.materiais WHERE active = 1;
    WHEN 'maquinas_count' THEN
      SELECT jsonb_build_array(jsonb_build_object('total', COUNT(*))) INTO result FROM public.maquinas;
    WHEN 'maquinas_by_type' THEN
      SELECT COALESCE(jsonb_agg(to_jsonb(row_value)), '[]'::jsonb) INTO result FROM (
        SELECT tipo, COUNT(*) AS total FROM public.maquinas
        WHERE active = 1 GROUP BY tipo
      ) AS row_value;
    WHEN 'maquinas_hour_cost' THEN
      SELECT jsonb_build_array(jsonb_build_object('total', SUM(custo_total_hora))) INTO result
        FROM public.maquinas WHERE active = 1;
    WHEN 'insumos_by_category' THEN
      SELECT COALESCE(jsonb_agg(to_jsonb(row_value)), '[]'::jsonb) INTO result FROM (
        SELECT categoria, SUM(quantidade) AS total FROM public.insumos
        WHERE active = 1 GROUP BY categoria
      ) AS row_value;
    WHEN 'insumos_totals' THEN
      SELECT jsonb_agg(to_jsonb(row_value)) INTO result FROM (
        SELECT COUNT(*) AS total_itens, SUM(quantidade) AS total_quantidade,
          SUM(quantidade * preco_unitario) AS valor_total,
          COUNT(CASE WHEN quantidade <= estoque_minimo THEN 1 END) AS itens_baixos,
          COUNT(CASE WHEN quantidade <= 0 THEN 1 END) AS itens_esgotados
        FROM public.insumos WHERE active = 1
      ) AS row_value;
    WHEN 'pontos_employee_month' THEN
      SELECT COALESCE(jsonb_agg(to_jsonb(row_value)), '[]'::jsonb) INTO result FROM (
        SELECT * FROM public.pontos
        WHERE employee_id = (arguments->>0)::bigint
          AND left(data, 7) = arguments->>1
        ORDER BY data DESC
      ) AS row_value;
    WHEN 'pontos_month_summary' THEN
      SELECT jsonb_agg(to_jsonb(row_value)) INTO result FROM (
        SELECT COUNT(*) AS dias_trabalhados,
          SUM(horas_trabalhadas) AS total_horas,
          SUM(horas_extras) AS total_horas_extras
        FROM public.pontos
        WHERE employee_id = (arguments->>0)::bigint
          AND left(data, 7) = arguments->>1
      ) AS row_value;
    WHEN 'order_items_for_orders' THEN
      SELECT COALESCE(jsonb_agg(to_jsonb(row_value)), '[]'::jsonb) INTO result FROM (
        SELECT item.*, product.nome AS produto_nome
        FROM public.order_items AS item
        LEFT JOIN public.products AS product ON product.id = item.product_id
        WHERE item.order_id IN (
          SELECT jsonb_array_elements_text(arguments)::bigint
        )
      ) AS row_value;
    WHEN 'holerites_month_summary' THEN
      SELECT jsonb_agg(to_jsonb(row_value)) INTO result FROM (
        SELECT COUNT(*) AS total_funcionarios,
          SUM(salario_liquido) AS total_pagar,
          COUNT(CASE WHEN pago = 1 THEN 1 END) AS pagos,
          COUNT(CASE WHEN pago = 0 THEN 1 END) AS pendentes
        FROM public.holerites WHERE mes_referencia = arguments->>0
      ) AS row_value;
    WHEN 'composicoes_count' THEN
      SELECT jsonb_build_array(jsonb_build_object('total', COUNT(*))) INTO result FROM public.composicoes;
    WHEN 'composicoes_margin_average' THEN
      SELECT jsonb_build_array(jsonb_build_object('media', AVG(margem_lucro))) INTO result FROM public.composicoes;
    WHEN 'composicoes_cost_total' THEN
      SELECT jsonb_build_array(jsonb_build_object('total', SUM(custo_total))) INTO result FROM public.composicoes;
    WHEN 'composicoes_sales_total' THEN
      SELECT jsonb_build_array(jsonb_build_object('total', SUM(preco_venda))) INTO result FROM public.composicoes;
    ELSE
      RAISE EXCEPTION 'Relatório não permitido.' USING ERRCODE = '22023';
  END CASE;
  RETURN COALESCE(result, '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.matterdi_batch(
  operations jsonb,
  no_result boolean DEFAULT false,
  continue_on_error boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  item jsonb;
  item_result jsonb;
  results jsonb := '[]'::jsonb;
BEGIN
  IF operations IS NULL OR jsonb_typeof(operations) <> 'array'
     OR jsonb_array_length(operations) > 1000 THEN
    RAISE EXCEPTION 'Lote inválido.' USING ERRCODE = '22023';
  END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(operations)
  LOOP
    BEGIN
      IF item->>'kind' = 'data' THEN
        item_result := public.matterdi_data(item->'payload');
      ELSIF item->>'kind' = 'report' THEN
        item_result := public.matterdi_report(
          item->>'report_name', COALESCE(item->'arguments', '[]'::jsonb)
        );
      ELSE
        RAISE EXCEPTION 'Operação de lote não permitida.' USING ERRCODE = '22023';
      END IF;
      IF NOT no_result THEN results := results || jsonb_build_array(item_result); END IF;
    EXCEPTION WHEN OTHERS THEN
      IF NOT continue_on_error THEN RAISE; END IF;
      IF NOT no_result THEN
        results := results || jsonb_build_array(jsonb_build_object('error', SQLERRM));
      END IF;
    END;
  END LOOP;
  RETURN results;
END;
$$;

CREATE OR REPLACE FUNCTION public.matterdi_health()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'service', 'matterdi-supabase',
    'protocol', 1,
    'version', 27,
    'ready',
      to_regclass('public.system_users') IS NOT NULL
      AND to_regprocedure('public.matterdi_data(jsonb)') IS NOT NULL
      AND to_regprocedure('public.matterdi_report(text,jsonb)') IS NOT NULL
      AND to_regprocedure('public.matterdi_batch(jsonb,boolean,boolean)') IS NOT NULL
      AND to_regprocedure('public.matterdi_is_active_user()') IS NOT NULL
      AND to_regprocedure('public.matterdi_has_permission(text)') IS NOT NULL
      AND to_regprocedure('public.matterdi_order_create(jsonb,jsonb,jsonb)') IS NOT NULL
      AND to_regprocedure('public.matterdi_order_update(bigint,jsonb,jsonb,jsonb)') IS NOT NULL
      AND to_regprocedure('public.matterdi_order_approve(bigint,jsonb,jsonb)') IS NOT NULL
      AND to_regprocedure('public.matterdi_order_delete(bigint)') IS NOT NULL
      AND to_regprocedure('public.matterdi_stock_move(bigint,double precision,text,text,bigint,bigint,bigint,text)') IS NOT NULL
      AND to_regprocedure('public.matterdi_financial_partial(bigint,double precision,text)') IS NOT NULL
      AND to_regprocedure('public.matterdi_financial_from_order(bigint,jsonb)') IS NOT NULL
      AND to_regprocedure('public.matterdi_product_bulk_insert(jsonb)') IS NOT NULL
      AND to_regprocedure('public.matterdi_product_delete_many(jsonb)') IS NOT NULL
      AND to_regprocedure('public.matterdi_agenda_complete_next(bigint,jsonb,jsonb)') IS NOT NULL
      AND to_regprocedure('public.matterdi_composition_save(bigint,jsonb,jsonb)') IS NOT NULL
      AND to_regprocedure('public.matterdi_holerite_save(bigint,jsonb,jsonb)') IS NOT NULL
  );
$$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA matterdi_private FROM PUBLIC, anon;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA matterdi_private TO authenticated;

REVOKE ALL ON FUNCTION public.matterdi_data(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.matterdi_report(text, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.matterdi_batch(jsonb, boolean, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.matterdi_data(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.matterdi_report(text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.matterdi_batch(jsonb, boolean, boolean) TO authenticated;

REVOKE ALL ON FUNCTION public.matterdi_health() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.matterdi_health() TO anon, authenticated;
