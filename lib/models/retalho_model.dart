// lib/models/retalho_model.dart

import 'package:flutter/material.dart';

class RetalhoModel {
  int? id;
  int materialId;
  String codigo;
  String nome;

  // Dimensões do retalho
  double largura; // mm
  double altura; // mm
  double area; // m²

  // Origem
  int? pedidoOrigemId;
  String pedidoOrigemNumero;

  // Localização
  String localizacao;
  String prateleira;

  double valorEstimado;
  double valorVenda;

  String status; // 'disponivel', 'reservado', 'utilizado', 'descartado'

  String observacoes;
  String dataCriacao;
  String dataAtualizacao;

  RetalhoModel({
    this.id,
    required this.materialId,
    required this.codigo,
    required this.nome,
    this.largura = 0,
    this.altura = 0,
    this.area = 0,
    this.pedidoOrigemId,
    this.pedidoOrigemNumero = '',
    this.localizacao = '',
    this.prateleira = '',
    this.valorEstimado = 0,
    this.valorVenda = 0,
    this.status = 'disponivel',
    this.observacoes = '',
    String? dataCriacao,
    String? dataAtualizacao,
  })  : dataCriacao = dataCriacao ?? DateTime.now().toIso8601String(),
        dataAtualizacao = dataAtualizacao ?? DateTime.now().toIso8601String();

  factory RetalhoModel.fromMap(Map<String, dynamic> map) {
    return RetalhoModel(
      id: map['id'],
      materialId: map['material_id'] ?? 0,
      codigo: map['codigo'] ?? '',
      nome: map['nome'] ?? '',
      largura: (map['largura'] ?? 0).toDouble(),
      altura: (map['altura'] ?? 0).toDouble(),
      area: (map['area'] ?? 0).toDouble(),
      pedidoOrigemId: map['pedido_origem_id'],
      pedidoOrigemNumero: map['pedido_origem_numero'] ?? '',
      localizacao: map['localizacao'] ?? '',
      prateleira: map['prateleira'] ?? '',
      valorEstimado: (map['valor_estimado'] ?? 0).toDouble(),
      valorVenda: (map['valor_venda'] ?? 0).toDouble(),
      status: map['status'] ?? 'disponivel',
      observacoes: map['observacoes'] ?? '',
      dataCriacao: map['created_at'],
      dataAtualizacao: map['updated_at'],
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'material_id': materialId,
        'codigo': codigo,
        'nome': nome,
        'largura': largura,
        'altura': altura,
        'area': area,
        'pedido_origem_id': pedidoOrigemId,
        'pedido_origem_numero': pedidoOrigemNumero,
        'localizacao': localizacao,
        'prateleira': prateleira,
        'valor_estimado': valorEstimado,
        'valor_venda': valorVenda,
        'status': status,
        'observacoes': observacoes,
        'created_at': dataCriacao,
        'updated_at': dataAtualizacao,
      };

  // ============================================================
  // CALCULAR ÁREA
  // ============================================================
  double calcularArea() {
    if (largura > 0 && altura > 0) {
      return (largura * altura) / 1000000; // mm² m²
    }
    return area;
  }

  // ============================================================
  // STATUS - NOME COM EMOJI
  // ============================================================
  String getStatusNome() {
    switch (status) {
      case 'disponivel':
        return 'Disponível';
      case 'reservado':
        return 'Reservado';
      case 'utilizado':
        return 'Utilizado';
      case 'descartado':
        return 'Descartado';
      default:
        return status;
    }
  }

  // ============================================================
  // STATUS - COR
  // ============================================================
  Color getStatusColor() {
    switch (status) {
      case 'disponivel':
        return Colors.green;
      case 'reservado':
        return Colors.orange;
      case 'utilizado':
        return Colors.blue;
      case 'descartado':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // ============================================================
  // DIMENSÃO FORMATADA
  // ============================================================
  String getDimensaoString() {
    if (largura > 0 && altura > 0) {
      return '${largura.toStringAsFixed(0)} × ${altura.toStringAsFixed(0)} mm';
    }
    return '';
  }

  // ============================================================
  // LISTA DE STATUS DISPONÍVEIS
  // ============================================================
  static List<String> getStatusList() {
    return ['disponivel', 'reservado', 'utilizado', 'descartado'];
  }

  // ============================================================
  // COPIA PARA ATUALIZAÇÃO
  // ============================================================
  RetalhoModel copyWith({
    int? id,
    int? materialId,
    String? codigo,
    String? nome,
    double? largura,
    double? altura,
    double? area,
    int? pedidoOrigemId,
    String? pedidoOrigemNumero,
    String? localizacao,
    String? prateleira,
    double? valorEstimado,
    double? valorVenda,
    String? status,
    String? observacoes,
    String? dataCriacao,
    String? dataAtualizacao,
  }) {
    return RetalhoModel(
      id: id ?? this.id,
      materialId: materialId ?? this.materialId,
      codigo: codigo ?? this.codigo,
      nome: nome ?? this.nome,
      largura: largura ?? this.largura,
      altura: altura ?? this.altura,
      area: area ?? this.area,
      pedidoOrigemId: pedidoOrigemId ?? this.pedidoOrigemId,
      pedidoOrigemNumero: pedidoOrigemNumero ?? this.pedidoOrigemNumero,
      localizacao: localizacao ?? this.localizacao,
      prateleira: prateleira ?? this.prateleira,
      valorEstimado: valorEstimado ?? this.valorEstimado,
      valorVenda: valorVenda ?? this.valorVenda,
      status: status ?? this.status,
      observacoes: observacoes ?? this.observacoes,
      dataCriacao: dataCriacao ?? this.dataCriacao,
      dataAtualizacao: dataAtualizacao ?? this.dataAtualizacao,
    );
  }

  // ============================================================
  // TO STRING
  // ============================================================
  @override
  String toString() {
    return 'RetalhoModel{id: $id, codigo: $codigo, nome: $nome, area: $area, status: $status}';
  }
}
