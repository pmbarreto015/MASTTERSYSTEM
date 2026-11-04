-- Operações de negócio que precisam ser atômicas no PostgreSQL.
-- Todas as funções públicas validam o usuário do Supabase Auth e sua
-- permissão antes de tocar nas tabelas. O search_path vazio evita que objetos
-- criados por terceiros sejam resolvidos durante uma função SECURITY DEFINER.

ALTER TABLE public.composicao_itens
  ADD COLUMN IF NOT EXISTS item_id BIGINT;
ALTER TABLE public.composicao_itens
  ADD COLUMN IF NOT EXISTS item_original_id BIGINT;

CREATE OR REPLACE FUNCTION public.matterdi_insert_financial_rows(
  p_order_id BIGINT,
  p_rows JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_item JSONB;
  v_inserted public.financial%ROWTYPE;
  v_result JSONB := '[]'::JSONB;
BEGIN
  IF p_rows IS NULL OR p_rows = 'null'::JSONB THEN
    RETURN v_result;
  END IF;
  IF jsonb_typeof(p_rows) <> 'array' THEN
    RAISE EXCEPTION 'A lista de lançamentos financeiros é inválida.'
      USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_rows) > 500 THEN
    RAISE EXCEPTION 'A operação excede 500 lançamentos financeiros.'
      USING ERRCODE = '54000';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_rows)
  LOOP
    IF jsonb_typeof(v_item) <> 'object' THEN
      RAISE EXCEPTION 'Lançamento financeiro inválido.'
        USING ERRCODE = '22023';
    END IF;

    INSERT INTO public.financial (
      description, amount, type, due_date, is_paid, notes, order_id,
      customer_id, customer_name, categoria, forma_pagamento, parcela,
      total_parcelas, valor_bruto, taxa, valor_liquido, status, pagamentos,
      created_at, updated_at
    ) VALUES (
      v_item->>'description',
      (v_item->>'amount')::DOUBLE PRECISION,
      v_item->>'type',
      v_item->>'due_date',
      COALESCE(NULLIF(v_item->>'is_paid', '')::BIGINT, 0),
      v_item->>'notes',
      COALESCE(p_order_id, NULLIF(v_item->>'order_id', '')::BIGINT),
      NULLIF(v_item->>'customer_id', '')::BIGINT,
      v_item->>'customer_name',
      COALESCE(v_item->>'categoria', 'outros'),
      COALESCE(v_item->>'forma_pagamento', ''),
      COALESCE(NULLIF(v_item->>'parcela', '')::BIGINT, 0),
      COALESCE(NULLIF(v_item->>'total_parcelas', '')::BIGINT, 0),
      COALESCE(NULLIF(v_item->>'valor_bruto', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(v_item->>'taxa', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(v_item->>'valor_liquido', '')::DOUBLE PRECISION, 0),
      COALESCE(v_item->>'status', 'pendente'),
      COALESCE(v_item->>'pagamentos', ''),
      COALESCE(
        v_item->>'created_at',
        to_char(clock_timestamp() AT TIME ZONE 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
      ),
      COALESCE(
        v_item->>'updated_at',
        to_char(clock_timestamp() AT TIME ZONE 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
      )
    )
    RETURNING * INTO v_inserted;

    v_result := v_result || jsonb_build_array(to_jsonb(v_inserted));
  END LOOP;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.matterdi_insert_financial_rows(BIGINT, JSONB)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.matterdi_order_create(
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
  v_order_id BIGINT;
  v_item JSONB;
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.matterdi_has_permission('vendas') THEN
    RAISE EXCEPTION 'Sem permissão para criar pedidos.'
      USING ERRCODE = '42501';
  END IF;
  IF jsonb_typeof(p_order) <> 'object'
     OR jsonb_typeof(p_items) <> 'array'
     OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Pedido ou itens inválidos.' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_items) > 1000 THEN
    RAISE EXCEPTION 'O pedido excede 1000 itens.' USING ERRCODE = '54000';
  END IF;

  INSERT INTO public.orders (
    number, tipo, cliente_nome, customer_id, seller_id, total, discount,
    entrada, parcelas, parcelas_datas, valor_manual, prioridade,
    payment_method, status, observations, delivery_date, created_at, updated_at
  ) VALUES (
    p_order->>'number',
    p_order->>'tipo',
    p_order->>'cliente_nome',
    (p_order->>'customer_id')::BIGINT,
    NULLIF(p_order->>'seller_id', '')::BIGINT,
    (p_order->>'total')::DOUBLE PRECISION,
    COALESCE(NULLIF(p_order->>'discount', '')::DOUBLE PRECISION, 0),
    COALESCE(NULLIF(p_order->>'entrada', '')::DOUBLE PRECISION, 0),
    COALESCE(p_order->>'parcelas', ''),
    COALESCE(p_order->>'parcelas_datas', ''),
    COALESCE(NULLIF(p_order->>'valor_manual', '')::DOUBLE PRECISION, 0),
    COALESCE(p_order->>'prioridade', 'normal'),
    p_order->>'payment_method',
    p_order->>'status',
    p_order->>'observations',
    p_order->>'delivery_date',
    p_order->>'created_at',
    p_order->>'updated_at'
  )
  RETURNING id INTO v_order_id;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO public.order_items (
      order_id, product_id, quantity, unit_price, subtotal, specifications,
      largura, altura, custo_unitario, detalhes_custo, terceirizado
    ) VALUES (
      v_order_id,
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

  IF COALESCE(p_order->>'tipo', '') = 'OS' THEN
    PERFORM public.matterdi_insert_financial_rows(v_order_id, p_financials);
  END IF;

  RETURN v_order_id;
END;
$$;

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

  IF p_order->>'status' IN ('pagamento_recebido', 'em_producao')
     AND NOT EXISTS (
       SELECT 1 FROM public.financial WHERE order_id = p_order_id
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
    SELECT 1 FROM public.financial WHERE order_id = p_order_id
  ) THEN
    PERFORM public.matterdi_insert_financial_rows(p_order_id, p_financials);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.matterdi_order_delete(p_order_id BIGINT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_seller_id BIGINT;
  v_deleted BIGINT;
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.matterdi_has_permission('pedidos_excluir') THEN
    RAISE EXCEPTION 'Sem permissão para excluir pedidos.'
      USING ERRCODE = '42501';
  END IF;

  SELECT seller_id INTO v_seller_id
    FROM public.orders
   WHERE id = p_order_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  DELETE FROM public.composicao_itens
   WHERE composicao_id IN (
     SELECT id FROM public.composicoes
      WHERE pedido_id = p_order_id OR orcamento_id = p_order_id
   );
  DELETE FROM public.composicoes
   WHERE pedido_id = p_order_id OR orcamento_id = p_order_id;
  DELETE FROM public.financial WHERE order_id = p_order_id;
  DELETE FROM public.stock_movements WHERE order_id = p_order_id;
  DELETE FROM public.retalhos WHERE pedido_origem_id = p_order_id;
  DELETE FROM public.order_items WHERE order_id = p_order_id;
  DELETE FROM public.orders WHERE id = p_order_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  IF v_seller_id IS NOT NULL THEN
    UPDATE public.sellers SET
      total_sales = COALESCE((
        SELECT SUM(total)
          FROM public.orders
         WHERE seller_id = v_seller_id AND status <> 'cancelado'
      ), 0),
      updated_at = to_char(clock_timestamp() AT TIME ZONE 'UTC',
                           'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    WHERE id = v_seller_id;
  END IF;

  RETURN v_deleted;
END;
$$;

CREATE OR REPLACE FUNCTION public.matterdi_stock_move(
  p_product_id BIGINT,
  p_quantity DOUBLE PRECISION,
  p_kind TEXT,
  p_reason TEXT,
  p_supplier_id BIGINT,
  p_order_id BIGINT,
  p_user_id BIGINT,
  p_created_at TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_product public.products%ROWTYPE;
  v_new_stock DOUBLE PRECISION;
  v_movement_quantity DOUBLE PRECISION;
  v_actor_id BIGINT;
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.matterdi_has_permission('estoque') THEN
    RAISE EXCEPTION 'Sem permissão para movimentar estoque.'
      USING ERRCODE = '42501';
  END IF;
  IF p_kind NOT IN ('compra', 'entrada', 'venda', 'saida', 'ajuste')
     OR p_quantity IS NULL
     OR p_quantity::TEXT IN ('NaN', 'Infinity', '-Infinity') THEN
    RAISE EXCEPTION 'Movimentação de estoque inválida.'
      USING ERRCODE = '22023';
  END IF;
  IF (p_kind = 'ajuste' AND p_quantity < 0)
     OR (p_kind <> 'ajuste' AND p_quantity <= 0) THEN
    RAISE EXCEPTION 'A quantidade informada é inválida.'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_product
    FROM public.products
   WHERE id = p_product_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Produto não encontrado.' USING ERRCODE = 'P0002';
  END IF;

  IF p_kind = 'ajuste' THEN
    v_new_stock := p_quantity;
    v_movement_quantity := abs(p_quantity - COALESCE(v_product.estoque, 0));
  ELSIF p_kind IN ('compra', 'entrada') THEN
    v_new_stock := COALESCE(v_product.estoque, 0) + p_quantity;
    v_movement_quantity := p_quantity;
  ELSE
    v_new_stock := COALESCE(v_product.estoque, 0) - p_quantity;
    v_movement_quantity := p_quantity;
  END IF;

  IF v_new_stock < 0 THEN
    RAISE EXCEPTION 'Estoque insuficiente. Disponível: %', v_product.estoque
      USING ERRCODE = '22023';
  END IF;

  SELECT id INTO v_actor_id
    FROM public.system_users
   WHERE auth_user_id = auth.uid() AND active = 1
   LIMIT 1;

  UPDATE public.products SET
    estoque = v_new_stock,
    updated_at = COALESCE(
      p_created_at,
      to_char(clock_timestamp() AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    )
  WHERE id = p_product_id;

  INSERT INTO public.stock_movements (
    product_id, product_name, quantity, type, previous_stock, new_stock,
    reason, order_id, supplier_id, user_id, created_at
  ) VALUES (
    p_product_id, v_product.nome, v_movement_quantity, p_kind,
    COALESCE(v_product.estoque, 0), v_new_stock, p_reason, p_order_id,
    p_supplier_id, v_actor_id,
    COALESCE(
      p_created_at,
      to_char(clock_timestamp() AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.matterdi_financial_partial(
  p_id BIGINT,
  p_paid DOUBLE PRECISION,
  p_date TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_current public.financial%ROWTYPE;
  v_updated public.financial%ROWTYPE;
  v_remaining DOUBLE PRECISION;
  v_now TEXT := to_char(clock_timestamp() AT TIME ZONE 'UTC',
                        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.matterdi_has_permission('financeiro') THEN
    RAISE EXCEPTION 'Sem permissão para registrar pagamentos.'
      USING ERRCODE = '42501';
  END IF;
  IF p_paid IS NULL
     OR p_paid::TEXT IN ('NaN', 'Infinity', '-Infinity')
     OR p_paid <= 0 THEN
    RAISE EXCEPTION 'O valor pago deve ser maior que zero.'
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_current
    FROM public.financial
   WHERE id = p_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transação não encontrada.' USING ERRCODE = 'P0002';
  END IF;
  IF v_current.is_paid = 1 OR v_current.amount <= 0 THEN
    RAISE EXCEPTION 'Esta transação já está quitada.' USING ERRCODE = 'P0001';
  END IF;
  IF p_paid > v_current.amount THEN
    RAISE EXCEPTION 'O pagamento não pode ser maior que o saldo em aberto.'
      USING ERRCODE = '22023';
  END IF;

  v_remaining := v_current.amount - p_paid;
  IF abs(v_remaining) < 0.000000001 THEN
    v_remaining := 0;
  END IF;

  INSERT INTO public.financial (
    description, amount, type, due_date, is_paid, notes, order_id,
    customer_id, customer_name, categoria, forma_pagamento, parcela,
    total_parcelas, valor_bruto, taxa, valor_liquido, status, pagamentos,
    created_at, updated_at
  ) VALUES (
    'Parcial - ' || v_current.description,
    p_paid,
    'receber',
    p_date,
    1,
    'Pagamento parcial de ' || v_current.amount::TEXT,
    v_current.order_id,
    v_current.customer_id,
    v_current.customer_name,
    v_current.categoria,
    v_current.forma_pagamento,
    0, 0, 0, 0, 0,
    'pago',
    '',
    v_now,
    v_now
  );

  UPDATE public.financial SET
    amount = v_remaining,
    is_paid = CASE WHEN v_remaining = 0 THEN 1 ELSE 0 END,
    status = CASE WHEN v_remaining = 0 THEN 'pago' ELSE 'parcial' END,
    updated_at = v_now
  WHERE id = p_id
  RETURNING * INTO v_updated;

  RETURN to_jsonb(v_updated);
END;
$$;

CREATE OR REPLACE FUNCTION public.matterdi_financial_from_order(
  p_order_id BIGINT,
  p_rows JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT (
    public.matterdi_has_permission('financeiro')
    OR public.matterdi_has_permission('vendas')
    OR public.matterdi_has_permission('orcamentos')
  ) THEN
    RAISE EXCEPTION 'Sem permissão para gerar o financeiro do pedido.'
      USING ERRCODE = '42501';
  END IF;
  IF p_order_id IS NULL THEN
    RAISE EXCEPTION 'Pedido sem identificador.' USING ERRCODE = '22023';
  END IF;

  PERFORM 1 FROM public.orders WHERE id = p_order_id FOR KEY SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido não encontrado.' USING ERRCODE = 'P0002';
  END IF;

  RETURN public.matterdi_insert_financial_rows(p_order_id, p_rows);
END;
$$;

CREATE OR REPLACE FUNCTION public.matterdi_product_bulk_insert(p_rows JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_item JSONB;
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.matterdi_has_permission('produtos') THEN
    RAISE EXCEPTION 'Sem permissão para cadastrar produtos.'
      USING ERRCODE = '42501';
  END IF;
  IF jsonb_typeof(p_rows) <> 'array' THEN
    RAISE EXCEPTION 'Lista de produtos inválida.' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_rows) > 10000 THEN
    RAISE EXCEPTION 'A importação excede 10000 produtos.'
      USING ERRCODE = '54000';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_rows)
  LOOP
    INSERT INTO public.products (
      codigo, nome, descricao, categoria, preco, cost, estoque, unidade,
      ativo, composicao_id, created_at, updated_at
    ) VALUES (
      v_item->>'codigo',
      v_item->>'nome',
      v_item->>'descricao',
      v_item->>'categoria',
      (v_item->>'preco')::DOUBLE PRECISION,
      COALESCE(NULLIF(v_item->>'cost', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(v_item->>'estoque', '')::DOUBLE PRECISION, 0),
      COALESCE(v_item->>'unidade', 'un'),
      COALESCE(NULLIF(v_item->>'ativo', '')::BIGINT, 1),
      NULLIF(v_item->>'composicao_id', '')::BIGINT,
      v_item->>'created_at',
      v_item->>'updated_at'
    );
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.matterdi_product_delete_many(p_ids JSONB)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_ids BIGINT[];
  v_deleted BIGINT;
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.matterdi_has_permission('produtos') THEN
    RAISE EXCEPTION 'Sem permissão para excluir produtos.'
      USING ERRCODE = '42501';
  END IF;
  IF jsonb_typeof(p_ids) <> 'array' THEN
    RAISE EXCEPTION 'Lista de produtos inválida.' USING ERRCODE = '22023';
  END IF;

  SELECT array_agg(DISTINCT value::BIGINT ORDER BY value::BIGINT)
    INTO v_ids
    FROM jsonb_array_elements_text(p_ids);
  IF COALESCE(array_length(v_ids, 1), 0) = 0 THEN
    RETURN 0;
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_ids) id WHERE id <= 0) THEN
    RAISE EXCEPTION 'Identificador de produto inválido.'
      USING ERRCODE = '22023';
  END IF;

  PERFORM 1
    FROM public.products
   WHERE id = ANY(v_ids)
   ORDER BY id
   FOR UPDATE;

  DELETE FROM public.composicao_itens
   WHERE composicao_id IN (
     SELECT id FROM public.composicoes WHERE produto_id = ANY(v_ids)
   );
  DELETE FROM public.composicoes WHERE produto_id = ANY(v_ids);
  DELETE FROM public.products WHERE id = ANY(v_ids);
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

CREATE OR REPLACE FUNCTION public.matterdi_agenda_complete_next(
  p_id BIGINT,
  p_completed JSONB,
  p_next JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.matterdi_has_permission('agenda') THEN
    RAISE EXCEPTION 'Sem permissão para alterar a agenda.'
      USING ERRCODE = '42501';
  END IF;

  SELECT status INTO v_status
    FROM public.agenda_followups
   WHERE id = p_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Compromisso não encontrado.' USING ERRCODE = 'P0002';
  END IF;
  -- Protege contra toque duplo/reenvio: a recorrência é criada uma única vez.
  IF v_status = 'concluido' THEN
    RETURN;
  END IF;

  UPDATE public.agenda_followups SET
    cliente_nome = p_completed->>'cliente_nome',
    telefone = COALESCE(p_completed->>'telefone', ''),
    assunto = p_completed->>'assunto',
    observacoes = COALESCE(p_completed->>'observacoes', ''),
    status = 'concluido',
    periodicidade = p_completed->>'periodicidade',
    agendado_para = p_completed->>'agendado_para',
    concluido_em = p_completed->>'concluido_em',
    updated_at = p_completed->>'updated_at'
  WHERE id = p_id;

  IF p_next IS NOT NULL AND p_next <> 'null'::JSONB THEN
    IF jsonb_typeof(p_next) <> 'object' THEN
      RAISE EXCEPTION 'Próximo compromisso inválido.' USING ERRCODE = '22023';
    END IF;
    INSERT INTO public.agenda_followups (
      cliente_nome, telefone, assunto, observacoes, status, periodicidade,
      agendado_para, concluido_em, created_at, updated_at
    ) VALUES (
      p_next->>'cliente_nome',
      COALESCE(p_next->>'telefone', ''),
      p_next->>'assunto',
      COALESCE(p_next->>'observacoes', ''),
      COALESCE(p_next->>'status', 'responder'),
      p_next->>'periodicidade',
      p_next->>'agendado_para',
      p_next->>'concluido_em',
      p_next->>'created_at',
      p_next->>'updated_at'
    );
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.matterdi_composition_save(
  p_id BIGINT,
  p_header JSONB,
  p_items JSONB
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id BIGINT;
  v_item JSONB;
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.matterdi_has_permission('corte_compositor') THEN
    RAISE EXCEPTION 'Sem permissão para salvar composições.'
      USING ERRCODE = '42501';
  END IF;
  IF jsonb_typeof(p_header) <> 'object'
     OR jsonb_typeof(p_items) <> 'array' THEN
    RAISE EXCEPTION 'Composição inválida.' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_items) > 2000 THEN
    RAISE EXCEPTION 'A composição excede 2000 itens.' USING ERRCODE = '54000';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.composicoes (
      pedido_id, orcamento_id, produto_id, custo_total_materiais,
      custo_total_maquinas, custo_total_servicos, custo_total, margem_lucro,
      preco_venda, observacoes, created_at, updated_at
    ) VALUES (
      NULLIF(p_header->>'pedido_id', '')::BIGINT,
      NULLIF(p_header->>'orcamento_id', '')::BIGINT,
      NULLIF(p_header->>'produto_id', '')::BIGINT,
      COALESCE(NULLIF(p_header->>'custo_total_materiais', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(p_header->>'custo_total_maquinas', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(p_header->>'custo_total_servicos', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(p_header->>'custo_total', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(p_header->>'margem_lucro', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(p_header->>'preco_venda', '')::DOUBLE PRECISION, 0),
      p_header->>'observacoes',
      p_header->>'created_at',
      p_header->>'updated_at'
    ) RETURNING id INTO v_id;
  ELSE
    PERFORM 1 FROM public.composicoes WHERE id = p_id FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Composição não encontrada.' USING ERRCODE = 'P0002';
    END IF;
    UPDATE public.composicoes SET
      pedido_id = NULLIF(p_header->>'pedido_id', '')::BIGINT,
      orcamento_id = NULLIF(p_header->>'orcamento_id', '')::BIGINT,
      produto_id = NULLIF(p_header->>'produto_id', '')::BIGINT,
      custo_total_materiais = COALESCE(NULLIF(p_header->>'custo_total_materiais', '')::DOUBLE PRECISION, 0),
      custo_total_maquinas = COALESCE(NULLIF(p_header->>'custo_total_maquinas', '')::DOUBLE PRECISION, 0),
      custo_total_servicos = COALESCE(NULLIF(p_header->>'custo_total_servicos', '')::DOUBLE PRECISION, 0),
      custo_total = COALESCE(NULLIF(p_header->>'custo_total', '')::DOUBLE PRECISION, 0),
      margem_lucro = COALESCE(NULLIF(p_header->>'margem_lucro', '')::DOUBLE PRECISION, 0),
      preco_venda = COALESCE(NULLIF(p_header->>'preco_venda', '')::DOUBLE PRECISION, 0),
      observacoes = p_header->>'observacoes',
      updated_at = p_header->>'updated_at'
    WHERE id = p_id;
    v_id := p_id;
    DELETE FROM public.composicao_itens WHERE composicao_id = v_id;
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    IF v_item->>'tipo' NOT IN ('material', 'maquina', 'servico') THEN
      RAISE EXCEPTION 'Tipo de item da composição inválido.'
        USING ERRCODE = '22023';
    END IF;
    INSERT INTO public.composicao_itens (
      composicao_id, tipo, descricao, quantidade, unidade, valor_unitario,
      valor_total, observacoes, item_id, item_original_id, created_at
    ) VALUES (
      v_id,
      v_item->>'tipo',
      v_item->>'descricao',
      COALESCE(NULLIF(v_item->>'quantidade', '')::DOUBLE PRECISION, 0),
      v_item->>'unidade',
      COALESCE(NULLIF(v_item->>'valor_unitario', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(v_item->>'valor_total', '')::DOUBLE PRECISION, 0),
      v_item->>'observacoes',
      NULLIF(v_item->>'item_id', '')::BIGINT,
      NULLIF(v_item->>'item_original_id', '')::BIGINT,
      COALESCE(
        v_item->>'created_at',
        to_char(clock_timestamp() AT TIME ZONE 'UTC',
                'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
      )
    );
  END LOOP;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.matterdi_holerite_save(
  p_id BIGINT,
  p_row JSONB,
  p_financial JSONB
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id BIGINT;
  v_current public.holerites%ROWTYPE;
  v_saved public.holerites%ROWTYPE;
  v_financial JSONB;
BEGIN
  IF auth.uid() IS NULL
     OR NOT public.matterdi_has_permission('funcionarios') THEN
    RAISE EXCEPTION 'Sem permissão para salvar holerites.'
      USING ERRCODE = '42501';
  END IF;
  IF jsonb_typeof(p_row) <> 'object' THEN
    RAISE EXCEPTION 'Holerite inválido.' USING ERRCODE = '22023';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.holerites (
      employee_id, employee_name, mes_referencia, salario_base,
      horas_trabalhadas, horas_extras, valor_hora, valor_hora_extra,
      total_horas_extras, salario_bruto, descontos, vale_transporte,
      vale_alimentacao, insalubridade, periculosidade, comissao, outros,
      inss, irrf, salario_liquido, observacoes, pago, created_at, updated_at
    ) VALUES (
      (p_row->>'employee_id')::BIGINT,
      p_row->>'employee_name',
      p_row->>'mes_referencia',
      COALESCE(NULLIF(p_row->>'salario_base', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(p_row->>'horas_trabalhadas', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(p_row->>'horas_extras', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(p_row->>'valor_hora', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(p_row->>'valor_hora_extra', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(p_row->>'total_horas_extras', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(p_row->>'salario_bruto', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(p_row->>'descontos', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(p_row->>'vale_transporte', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(p_row->>'vale_alimentacao', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(p_row->>'insalubridade', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(p_row->>'periculosidade', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(p_row->>'comissao', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(p_row->>'outros', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(p_row->>'inss', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(p_row->>'irrf', '')::DOUBLE PRECISION, 0),
      COALESCE(NULLIF(p_row->>'salario_liquido', '')::DOUBLE PRECISION, 0),
      COALESCE(p_row->>'observacoes', ''),
      COALESCE(NULLIF(p_row->>'pago', '')::BIGINT, 0),
      p_row->>'created_at',
      p_row->>'updated_at'
    ) RETURNING * INTO v_saved;
    v_id := v_saved.id;

    IF v_saved.salario_liquido > 0 THEN
      IF p_financial IS NULL OR p_financial = 'null'::JSONB
         OR jsonb_typeof(p_financial) <> 'object' THEN
        RAISE EXCEPTION 'O lançamento financeiro do holerite é obrigatório.'
          USING ERRCODE = '22023';
      END IF;
      v_financial := p_financial
        || jsonb_build_object(
          'amount', v_saved.salario_liquido,
          'type', 'pagar',
          'categoria', 'pessoal',
          'is_paid', v_saved.pago,
          'status', CASE WHEN v_saved.pago = 1 THEN 'pago' ELSE 'pendente' END
        );
      PERFORM public.matterdi_insert_financial_rows(NULL, jsonb_build_array(v_financial));
    END IF;
  ELSE
    SELECT * INTO v_current
      FROM public.holerites
     WHERE id = p_id
     FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Holerite não encontrado.' USING ERRCODE = 'P0002';
    END IF;

    UPDATE public.holerites SET
      employee_id = CASE WHEN p_row ? 'employee_id'
        THEN (p_row->>'employee_id')::BIGINT ELSE v_current.employee_id END,
      employee_name = CASE WHEN p_row ? 'employee_name'
        THEN p_row->>'employee_name' ELSE v_current.employee_name END,
      mes_referencia = CASE WHEN p_row ? 'mes_referencia'
        THEN p_row->>'mes_referencia' ELSE v_current.mes_referencia END,
      salario_base = CASE WHEN p_row ? 'salario_base'
        THEN (p_row->>'salario_base')::DOUBLE PRECISION ELSE v_current.salario_base END,
      horas_trabalhadas = CASE WHEN p_row ? 'horas_trabalhadas'
        THEN (p_row->>'horas_trabalhadas')::DOUBLE PRECISION ELSE v_current.horas_trabalhadas END,
      horas_extras = CASE WHEN p_row ? 'horas_extras'
        THEN (p_row->>'horas_extras')::DOUBLE PRECISION ELSE v_current.horas_extras END,
      valor_hora = CASE WHEN p_row ? 'valor_hora'
        THEN (p_row->>'valor_hora')::DOUBLE PRECISION ELSE v_current.valor_hora END,
      valor_hora_extra = CASE WHEN p_row ? 'valor_hora_extra'
        THEN (p_row->>'valor_hora_extra')::DOUBLE PRECISION ELSE v_current.valor_hora_extra END,
      total_horas_extras = CASE WHEN p_row ? 'total_horas_extras'
        THEN (p_row->>'total_horas_extras')::DOUBLE PRECISION ELSE v_current.total_horas_extras END,
      salario_bruto = CASE WHEN p_row ? 'salario_bruto'
        THEN (p_row->>'salario_bruto')::DOUBLE PRECISION ELSE v_current.salario_bruto END,
      descontos = CASE WHEN p_row ? 'descontos'
        THEN (p_row->>'descontos')::DOUBLE PRECISION ELSE v_current.descontos END,
      vale_transporte = CASE WHEN p_row ? 'vale_transporte'
        THEN (p_row->>'vale_transporte')::DOUBLE PRECISION ELSE v_current.vale_transporte END,
      vale_alimentacao = CASE WHEN p_row ? 'vale_alimentacao'
        THEN (p_row->>'vale_alimentacao')::DOUBLE PRECISION ELSE v_current.vale_alimentacao END,
      insalubridade = CASE WHEN p_row ? 'insalubridade'
        THEN (p_row->>'insalubridade')::DOUBLE PRECISION ELSE v_current.insalubridade END,
      periculosidade = CASE WHEN p_row ? 'periculosidade'
        THEN (p_row->>'periculosidade')::DOUBLE PRECISION ELSE v_current.periculosidade END,
      comissao = CASE WHEN p_row ? 'comissao'
        THEN (p_row->>'comissao')::DOUBLE PRECISION ELSE v_current.comissao END,
      outros = CASE WHEN p_row ? 'outros'
        THEN (p_row->>'outros')::DOUBLE PRECISION ELSE v_current.outros END,
      inss = CASE WHEN p_row ? 'inss'
        THEN (p_row->>'inss')::DOUBLE PRECISION ELSE v_current.inss END,
      irrf = CASE WHEN p_row ? 'irrf'
        THEN (p_row->>'irrf')::DOUBLE PRECISION ELSE v_current.irrf END,
      salario_liquido = CASE WHEN p_row ? 'salario_liquido'
        THEN (p_row->>'salario_liquido')::DOUBLE PRECISION ELSE v_current.salario_liquido END,
      observacoes = CASE WHEN p_row ? 'observacoes'
        THEN COALESCE(p_row->>'observacoes', '') ELSE v_current.observacoes END,
      pago = CASE WHEN p_row ? 'pago'
        THEN (p_row->>'pago')::BIGINT ELSE v_current.pago END,
      updated_at = CASE WHEN p_row ? 'updated_at'
        THEN p_row->>'updated_at' ELSE v_current.updated_at END
    WHERE id = p_id
    RETURNING * INTO v_saved;
    v_id := p_id;

    IF v_saved.pago = 1 THEN
      UPDATE public.financial SET
        is_paid = 1,
        status = 'pago',
        updated_at = v_saved.updated_at
      WHERE type = 'pagar'
        AND is_paid = 0
        AND notes = 'Holerite gerado automaticamente - ' || v_saved.mes_referencia
        AND right(description, char_length(' - ' || v_saved.employee_name))
            = ' - ' || v_saved.employee_name;
    END IF;
  END IF;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.matterdi_order_create(JSONB, JSONB, JSONB)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.matterdi_order_update(BIGINT, JSONB, JSONB, JSONB)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.matterdi_order_approve(BIGINT, JSONB, JSONB)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.matterdi_order_delete(BIGINT)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.matterdi_stock_move(
  BIGINT, DOUBLE PRECISION, TEXT, TEXT, BIGINT, BIGINT, BIGINT, TEXT
) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.matterdi_financial_partial(BIGINT, DOUBLE PRECISION, TEXT)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.matterdi_financial_from_order(BIGINT, JSONB)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.matterdi_product_bulk_insert(JSONB)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.matterdi_product_delete_many(JSONB)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.matterdi_agenda_complete_next(BIGINT, JSONB, JSONB)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.matterdi_composition_save(BIGINT, JSONB, JSONB)
  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.matterdi_holerite_save(BIGINT, JSONB, JSONB)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.matterdi_order_create(JSONB, JSONB, JSONB)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.matterdi_order_update(BIGINT, JSONB, JSONB, JSONB)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.matterdi_order_approve(BIGINT, JSONB, JSONB)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.matterdi_order_delete(BIGINT)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.matterdi_stock_move(
  BIGINT, DOUBLE PRECISION, TEXT, TEXT, BIGINT, BIGINT, BIGINT, TEXT
) TO authenticated;
GRANT EXECUTE ON FUNCTION public.matterdi_financial_partial(BIGINT, DOUBLE PRECISION, TEXT)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.matterdi_financial_from_order(BIGINT, JSONB)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.matterdi_product_bulk_insert(JSONB)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.matterdi_product_delete_many(JSONB)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.matterdi_agenda_complete_next(BIGINT, JSONB, JSONB)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.matterdi_composition_save(BIGINT, JSONB, JSONB)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.matterdi_holerite_save(BIGINT, JSONB, JSONB)
  TO authenticated;
