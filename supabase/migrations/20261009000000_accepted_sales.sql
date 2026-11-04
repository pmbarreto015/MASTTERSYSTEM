-- Preserva os registros financeiros; cancela somente títulos em aberto da OS que volta para orçamento.
CREATE OR REPLACE FUNCTION public.matterdi_order_update(
  p_order_id BIGINT,
  p_order JSONB,
  p_items JSONB,
  p_financials JSONB
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_item JSONB;
  v_exists BIGINT;
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.matterdi_has_permission('pedidos_alterar')
    OR public.matterdi_has_permission('producao')
    OR public.matterdi_has_permission('orcamentos')
  ) THEN
    RAISE EXCEPTION 'Sem permissão para alterar pedidos.'
      USING ERRCODE = '42501';
  END IF;
  IF p_order_id IS NULL
     OR jsonb_typeof(p_order) <> 'object'
     OR jsonb_typeof(p_items) <> 'array'
     OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Pedido ou itens inválidos.' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_items) > 1000 THEN
    RAISE EXCEPTION 'O pedido excede 1000 itens.' USING ERRCODE = '54000';
  END IF;

  SELECT id INTO v_exists
    FROM public.orders
   WHERE id = p_order_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido não encontrado.' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.orders SET
    number = p_order->>'number',
    tipo = p_order->>'tipo',
    cliente_nome = p_order->>'cliente_nome',
    customer_id = (p_order->>'customer_id')::BIGINT,
    seller_id = NULLIF(p_order->>'seller_id', '')::BIGINT,
    total = (p_order->>'total')::DOUBLE PRECISION,
    discount = COALESCE(NULLIF(p_order->>'discount', '')::DOUBLE PRECISION, 0),
    entrada = COALESCE(NULLIF(p_order->>'entrada', '')::DOUBLE PRECISION, 0),
    parcelas = COALESCE(p_order->>'parcelas', ''),
    parcelas_datas = COALESCE(p_order->>'parcelas_datas', ''),
    valor_manual = COALESCE(NULLIF(p_order->>'valor_manual', '')::DOUBLE PRECISION, 0),
    prioridade = COALESCE(p_order->>'prioridade', 'normal'),
    payment_method = p_order->>'payment_method',
    status = p_order->>'status',
    observations = p_order->>'observations',
    delivery_date = p_order->>'delivery_date',
    created_at = p_order->>'created_at',
    updated_at = p_order->>'updated_at'
  WHERE id = p_order_id;

  DELETE FROM public.order_items WHERE order_id = p_order_id;
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO public.order_items (
      order_id, product_id, quantity, unit_price, subtotal, specifications,
      largura, altura, custo_unitario, detalhes_custo, terceirizado
    ) VALUES (
      p_order_id,
      (v_item->>'product_id')::BIGINT,
      (v_item->>'quantity')::BIGINT,
      (v_item->>'unit_price')::DOUBLE PRECISION,
      (v_item->>'subtotal')::DOUBLE PRECISION,
      COALESCE(v_item->>'specifications', ''),
      COALESCE(NULLIF(v_item->>'largura', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(v_item->>'altura', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(v_item->>'custo_unitario', '')::DOUBLE PRECISION, 0),
      COALESCE(v_item->>'detalhes_custo', ''),
      COALESCE(NULLIF(v_item->>'terceirizado', '')::BIGINT, 0)
    );
  END LOOP;

  IF p_order->>'tipo' = 'OS' AND p_order->>'status' <> 'cancelado'
     AND NOT EXISTS (
       SELECT 1 FROM public.financial WHERE order_id = p_order_id AND status <> 'cancelado'
     ) THEN
    PERFORM public.matterdi_insert_financial_rows(p_order_id, p_financials);
  END IF;

  RETURN 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.matterdi_order_approve(
  p_order_id BIGINT,
  p_order JSONB,
  p_financials JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_current public.orders%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.matterdi_has_permission('orcamentos') THEN
    RAISE EXCEPTION 'Sem permissão para aprovar orçamentos.'
      USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_current
    FROM public.orders
   WHERE id = p_order_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Orçamento não encontrado.' USING ERRCODE = 'P0002';
  END IF;
  IF v_current.tipo <> 'ORCAMENTO'
     OR v_current.status <> 'aguardando_pagamento' THEN
    RAISE EXCEPTION 'Este orçamento já foi processado.'
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.orders SET
    number = p_order->>'number',
    tipo = 'OS',
    cliente_nome = p_order->>'cliente_nome',
    customer_id = (p_order->>'customer_id')::BIGINT,
    seller_id = NULLIF(p_order->>'seller_id', '')::BIGINT,
    total = (p_order->>'total')::DOUBLE PRECISION,
    discount = COALESCE(NULLIF(p_order->>'discount', '')::DOUBLE PRECISION, 0),
    entrada = COALESCE(NULLIF(p_order->>'entrada', '')::DOUBLE PRECISION, 0),
    parcelas = COALESCE(p_order->>'parcelas', ''),
    parcelas_datas = COALESCE(p_order->>'parcelas_datas', ''),
    valor_manual = COALESCE(NULLIF(p_order->>'valor_manual', '')::DOUBLE PRECISION, 0),
    prioridade = COALESCE(p_order->>'prioridade', 'normal'),
    payment_method = p_order->>'payment_method',
    status = 'pagamento_recebido',
    observations = p_order->>'observations',
    delivery_date = p_order->>'delivery_date',
    updated_at = p_order->>'updated_at'
  WHERE id = p_order_id;

  IF NOT EXISTS (
    SELECT 1 FROM public.financial WHERE order_id = p_order_id AND status <> 'cancelado'
  ) THEN
    PERFORM public.matterdi_insert_financial_rows(p_order_id, p_financials);
  END IF;
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
               AND sale.tipo = 'OS' AND sale.status <> 'cancelado'
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
        FROM (SELECT * FROM public.financial f WHERE f.status <> 'cancelado' AND (f.order_id IS NULL OR EXISTS(SELECT 1 FROM public.orders o WHERE o.id=f.order_id AND o.tipo='OS' AND o.status <> 'cancelado'))) financial WHERE customer_id = (arguments->>0)::bigint
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
        FROM (SELECT * FROM public.financial f WHERE f.status <> 'cancelado' AND (f.order_id IS NULL OR EXISTS(SELECT 1 FROM public.orders o WHERE o.id=f.order_id AND o.tipo='OS' AND o.status <> 'cancelado'))) financial
      ) AS row_value;
    WHEN 'financial_projection' THEN
      SELECT jsonb_agg(to_jsonb(row_value)) INTO result FROM (
        SELECT
          SUM(CASE WHEN type = 'receber' AND is_paid = 0 AND due_date BETWEEN arguments->>0 AND arguments->>1 THEN amount ELSE 0 END) AS a_receber_projetado,
          SUM(CASE WHEN type = 'pagar' AND is_paid = 0 AND due_date BETWEEN arguments->>2 AND arguments->>3 THEN amount ELSE 0 END) AS a_pagar_projetado
        FROM (SELECT * FROM public.financial f WHERE f.status <> 'cancelado' AND (f.order_id IS NULL OR EXISTS(SELECT 1 FROM public.orders o WHERE o.id=f.order_id AND o.tipo='OS' AND o.status <> 'cancelado'))) financial
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
        WHERE seller_id = (arguments->>0)::bigint AND tipo = 'OS' AND status <> 'cancelado'
      ) AS row_value;
    WHEN 'seller_sales_total' THEN
      SELECT jsonb_agg(to_jsonb(row_value)) INTO result FROM (
        SELECT COALESCE(SUM(total), 0) AS total_vendas
        FROM public.orders
        WHERE seller_id = (arguments->>0)::bigint AND tipo = 'OS' AND status <> 'cancelado'
      ) AS row_value;
    WHEN 'sales_by_seller' THEN
      SELECT COALESCE(jsonb_agg(to_jsonb(row_value)), '[]'::jsonb) INTO result FROM (
        SELECT seller.id, seller.name AS vendedor, seller.commission,
          seller.total_sales AS total_vendas,
          COALESCE(SUM(sale.total * seller.commission / 100), 0) AS total_comissao,
          COUNT(sale.id) AS quantidade_pedidos
        FROM public.sellers AS seller
        LEFT JOIN public.orders AS sale
          ON sale.seller_id = seller.id AND sale.tipo = 'OS' AND sale.status <> 'cancelado'
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



CREATE OR REPLACE FUNCTION public.matterdi_quote_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NEW.tipo NOT IN ('OS','ORCAMENTO') THEN RAISE EXCEPTION 'Tipo de documento inválido.' USING ERRCODE='22023'; END IF;
  IF NEW.tipo='ORCAMENTO' THEN
    IF TG_OP='UPDATE' AND OLD.tipo='OS' THEN
      IF EXISTS(SELECT 1 FROM public.financial WHERE order_id=OLD.id AND is_paid=1 AND amount>0) THEN
        RAISE EXCEPTION 'Esta OS possui recebimentos. Estorne os pagamentos antes de voltar para orçamento.' USING ERRCODE='22023';
      END IF;
      UPDATE public.financial SET status='cancelado',updated_at=NEW.updated_at
      WHERE order_id=OLD.id AND (is_paid=0 OR amount=0);
    END IF;
    IF NEW.status<>'cancelado' THEN NEW.status:='aguardando_pagamento'; END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS matterdi_quote_guard ON public.orders;
CREATE TRIGGER matterdi_quote_guard BEFORE INSERT OR UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.matterdi_quote_guard();
CREATE OR REPLACE FUNCTION public.matterdi_financial_quote_guard()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NEW.order_id IS NOT NULL AND NEW.status<>'cancelado' AND EXISTS(SELECT 1 FROM public.orders WHERE id=NEW.order_id AND tipo='ORCAMENTO') THEN
    RAISE EXCEPTION 'Orçamento precisa ser aceito e convertido em OS antes do financeiro.' USING ERRCODE='22023';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS matterdi_financial_quote_guard ON public.financial;
CREATE TRIGGER matterdi_financial_quote_guard BEFORE INSERT OR UPDATE ON public.financial FOR EACH ROW EXECUTE FUNCTION public.matterdi_financial_quote_guard();
CREATE OR REPLACE FUNCTION public.matterdi_refresh_accepted_sales()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_old BIGINT;v_new BIGINT;
BEGIN
  IF TG_OP<>'INSERT' THEN v_old:=OLD.seller_id; END IF;
  IF TG_OP<>'DELETE' THEN v_new:=NEW.seller_id; END IF;
  UPDATE public.sellers s SET total_sales=COALESCE((SELECT SUM(o.total) FROM public.orders o WHERE o.seller_id=s.id AND o.tipo='OS' AND o.status<>'cancelado'),0) WHERE s.id=v_old OR s.id=v_new;
  RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS matterdi_refresh_accepted_sales ON public.orders;
CREATE TRIGGER matterdi_refresh_accepted_sales AFTER INSERT OR UPDATE OR DELETE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.matterdi_refresh_accepted_sales();
REVOKE ALL ON FUNCTION public.matterdi_quote_guard() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.matterdi_financial_quote_guard() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.matterdi_refresh_accepted_sales() FROM PUBLIC,anon,authenticated;
UPDATE public.orders SET status='aguardando_pagamento' WHERE tipo='ORCAMENTO' AND status NOT IN ('aguardando_pagamento','cancelado');
UPDATE public.sellers s SET total_sales=COALESCE((SELECT SUM(o.total) FROM public.orders o WHERE o.seller_id=s.id AND o.tipo='OS' AND o.status<>'cancelado'),0);
