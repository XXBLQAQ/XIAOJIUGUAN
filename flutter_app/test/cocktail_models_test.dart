import 'package:flutter_test/flutter_test.dart';
import 'package:chat_game_app/features/cocktail/cocktail_notes_page.dart';
import 'package:chat_game_app/features/cocktail/cocktail_recipe_page.dart';

void main() {
  group('调酒笔记模型', () {
    test('可以序列化并恢复笔记', () {
      const note = CocktailNote(
        id: 'note-1',
        title: '夏日莫希托',
        body: '多加薄荷和碎冰',
        category: '夏日',
        tags: ['清爽', '朗姆'],
      );

      final restored = CocktailNote.fromJson(note.toJson());

      expect(restored.id, 'note-1');
      expect(restored.title, '夏日莫希托');
      expect(restored.tags, ['清爽', '朗姆']);
    });

    test('损坏字段使用安全默认值', () {
      final note = CocktailNote.fromJson({'title': '临时笔记'});

      expect(note.title, '临时笔记');
      expect(note.body, isEmpty);
      expect(note.category, '灵感');
      expect(note.tags, isEmpty);
    });
  });

  group('调酒配方模型', () {
    test('可以解析完整配方', () {
      final recipe = CocktailRecipe.fromJson({
        'name': '测试配方',
        'keywords': ['金酒'],
        'ingredients': ['金酒 45 ml'],
        'steps': ['搅拌'],
        'glass': '马天尼杯',
        'garnish': '柠檬皮',
        'taste': '干爽',
        'abv': 28,
      });

      expect(recipe.name, '测试配方');
      expect(recipe.ingredients.single, '金酒 45 ml');
      expect(recipe.abv, 28);
    });

    test('缺少列表或数字字段时不抛异常', () {
      final recipe = CocktailRecipe.fromJson({});

      expect(recipe.id, isNotEmpty);
      expect(recipe.name, '未命名配方');
      expect(recipe.ingredients, isEmpty);
      expect(recipe.abv, 0);
    });
  });
}
