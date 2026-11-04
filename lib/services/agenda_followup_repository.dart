import '../core/database/app_database.dart';
import '../core/database/supabase_database.dart';
import '../models/agenda_followup_model.dart';

class AgendaFollowupRepository {
  final AppDatabase _db = AppDatabase();

  Future<List<AgendaFollowupModel>> getAll() async {
    final database = await _db.database;
    final rows = await database.query(
      'agenda_followups',
      orderBy:
          "CASE WHEN status = 'concluido' THEN 1 ELSE 0 END, agendado_para ASC",
    );
    return rows.map(AgendaFollowupModel.fromMap).toList();
  }

  Future<AgendaFollowupModel> create(AgendaFollowupModel followup) async {
    final database = await _db.database;
    final map = followup.toMap()..remove('id');
    final id = await database.insert('agenda_followups', map);
    return followup.copyWith(id: id);
  }

  Future<void> update(AgendaFollowupModel followup) async {
    final database = await _db.database;
    final map = followup.toMap()
      ..remove('id')
      ..remove('created_at');
    await database.update(
      'agenda_followups',
      map,
      where: 'id = ?',
      whereArgs: [followup.id],
    );
  }

  Future<void> setCompleted(AgendaFollowupModel followup, bool completed) =>
      update(
        followup.copyWith(
          status: completed ? 'concluido' : 'responder',
          concluidoEm: completed ? DateTime.now() : null,
          limparConclusao: !completed,
        ),
      );

  Future<void> completeAndScheduleNext(AgendaFollowupModel followup) async {
    if (followup.id == null) {
      throw ArgumentError('Compromisso sem identificador.');
    }
    final database = await _db.database;
    final completed = followup.copyWith(
      status: 'concluido',
      concluidoEm: DateTime.now(),
    );
    final completedMap = completed.toMap()
      ..remove('id')
      ..remove('created_at');

    AgendaFollowupModel? next;
    if (followup.periodicidade != 'unico') {
      final now = DateTime.now();
      final recurrenceBase =
          followup.agendadoPara.isAfter(now) ? followup.agendadoPara : now;
      final nextDate = recurrenceBase.add(
        Duration(days: followup.periodicidade == 'diario' ? 1 : 7),
      );
      next = AgendaFollowupModel(
        clienteNome: followup.clienteNome,
        telefone: followup.telefone,
        assunto: followup.assunto,
        observacoes: followup.observacoes,
        status: 'responder',
        periodicidade: followup.periodicidade,
        agendadoPara: nextDate,
      );
    }

    if (database is SupabaseDatabase) {
      await database.rpc('matterdi_agenda_complete_next', {
        'p_id': followup.id,
        'p_completed': completedMap,
        'p_next': next == null ? null : (next.toMap()..remove('id')),
      });
      return;
    }

    await database.transaction((transaction) async {
      await transaction.update(
        'agenda_followups',
        completedMap,
        where: 'id = ?',
        whereArgs: [followup.id],
      );

      if (next == null) return;
      final nextMap = next.toMap()..remove('id');
      await transaction.insert('agenda_followups', nextMap);
    });
  }

  Future<void> delete(int id) async {
    final database = await _db.database;
    await database.delete(
      'agenda_followups',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
