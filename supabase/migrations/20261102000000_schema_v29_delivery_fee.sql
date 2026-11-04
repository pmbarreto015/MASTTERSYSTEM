-- Versão 29: mantém a taxa de entrega sem expor o financeiro ao operador de entregas.
CREATE INDEX IF NOT EXISTS idx_order_items_product_id
  ON public.order_items(product_id);
CREATE INDEX IF NOT EXISTS idx_orders_seller_id
  ON public.orders(seller_id);

CREATE OR REPLACE FUNCTION public.matterdi_delivery_fee(
  p_order_id BIGINT,
  p_fee DOUBLE PRECISION,
  p_due_date TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_active public.financial%ROWTYPE;
  v_marker TEXT := '[ENTREGA_FRETE:' || p_order_id::TEXT || ']';
  v_due TEXT := NULLIF(trim(COALESCE(p_due_date, '')), '');
  v_paid DOUBLE PRECISION := 0;
  v_pending DOUBLE PRECISION := 0;
  v_now TEXT := to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
BEGIN
  IF auth.uid() IS NULL OR NOT public.matterdi_has_permission('entregas') THEN
    RAISE EXCEPTION 'Sem permissão para ajustar a taxa de entrega.' USING ERRCODE = '42501';
  END IF;
  IF p_order_id IS NULL OR p_order_id < 1
     OR p_fee IS NULL OR p_fee::TEXT IN ('NaN', 'Infinity', '-Infinity')
     OR p_fee < 0 THEN
    RAISE EXCEPTION 'Taxa de entrega inválida.' USING ERRCODE = '22023';
  END IF;
  IF v_due IS NULL OR v_due !~ '^\d{4}-\d{2}-\d{2}' THEN
    RAISE EXCEPTION 'Informe uma data válida para a entrega.' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_order FROM public.orders
    WHERE id = p_order_id AND tipo = 'OS' AND status = 'entregue'
    FOR KEY SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Pedido de entrega não encontrado ou ainda não finalizado.' USING ERRCODE = 'P0002';
  END IF;

  SELECT COALESCE(SUM(amount), 0) INTO v_paid
    FROM public.financial
    WHERE order_id = p_order_id
      AND type = 'receber'
      AND status <> 'cancelado'
      AND is_paid = 1
      AND position(v_marker IN COALESCE(notes, '')) > 0;
  v_pending := GREATEST(p_fee - v_paid, 0);

  SELECT * INTO v_active FROM public.financial
    WHERE order_id = p_order_id
      AND type = 'receber'
      AND status <> 'cancelado'
      AND is_paid = 0
      AND position(v_marker IN COALESCE(notes, '')) > 0
    ORDER BY id
    LIMIT 1
    FOR UPDATE;

  IF v_pending <= .009 THEN
    UPDATE public.financial SET status = 'cancelado', updated_at = v_now
      WHERE order_id = p_order_id
        AND type = 'receber'
        AND status <> 'cancelado'
        AND is_paid = 0
        AND position(v_marker IN COALESCE(notes, '')) > 0;
    RETURN jsonb_build_object('pending_fee', 0);
  END IF;

  IF FOUND THEN
    UPDATE public.financial SET
      description = 'Taxa de entrega - Pedido ' || v_order.number,
      amount = v_pending,
      due_date = v_due,
      customer_name = COALESCE(v_order.cliente_nome, ''),
      forma_pagamento = COALESCE(v_order.payment_method, ''),
      status = 'pendente',
      updated_at = v_now
      WHERE id = v_active.id;
    UPDATE public.financial SET status = 'cancelado', updated_at = v_now
      WHERE order_id = p_order_id
        AND id <> v_active.id
        AND type = 'receber'
        AND status <> 'cancelado'
        AND is_paid = 0
        AND position(v_marker IN COALESCE(notes, '')) > 0;
  ELSE
    INSERT INTO public.financial (
      description, amount, type, due_date, is_paid, notes, order_id,
      customer_id, customer_name, categoria, forma_pagamento, parcela,
      total_parcelas, valor_bruto, taxa, valor_liquido, status, pagamentos,
      created_at, updated_at
    ) VALUES (
      'Taxa de entrega - Pedido ' || v_order.number,
      v_pending, 'receber', v_due, 0,
      v_marker || ' Taxa de entrega lançada pela expedição.', p_order_id,
      v_order.customer_id, COALESCE(v_order.cliente_nome, ''), 'entrega',
      COALESCE(v_order.payment_method, ''), 0, 0, 0, 0, 0, 'pendente', '',
      v_now, v_now
    );
  END IF;
  RETURN jsonb_build_object('pending_fee', v_pending);
END;
$$;
REVOKE ALL ON FUNCTION public.matterdi_delivery_fee(BIGINT, DOUBLE PRECISION, TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.matterdi_delivery_fee(BIGINT, DOUBLE PRECISION, TEXT)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.matterdi_health()
RETURNS JSONB LANGUAGE sql STABLE SECURITY INVOKER SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'service', 'matterdi-supabase', 'protocol', 1, 'version', 29, 'ready',
      to_regclass('public.system_users') IS NOT NULL
      AND to_regclass('public.erp_module_records') IS NOT NULL
      AND to_regclass('public.purchase_orders') IS NOT NULL
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
      AND to_regprocedure('public.matterdi_module_allowed(text)') IS NOT NULL
      AND to_regprocedure('public.matterdi_module_financial(bigint,jsonb)') IS NOT NULL
      AND to_regprocedure('public.matterdi_delivery_balances(jsonb)') IS NOT NULL
      AND to_regprocedure('public.matterdi_delivery_fee(bigint,double precision,text)') IS NOT NULL
  );
$$;
REVOKE ALL ON FUNCTION public.matterdi_health() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.matterdi_health() TO anon, authenticated;
