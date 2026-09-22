import 'package:flutter/material.dart';
import '../features/auth/splash_page.dart';
import '../features/auth/login_page.dart';
import '../features/chat/chat_list_page.dart';
import '../features/chat/chat_detail_page.dart';
import '../features/moments/moments_page.dart';
import '../features/home/home_page.dart';
import '../features/minecraft/minecraft_server_page.dart';
import '../features/travel/travel_planner_page.dart';
import '../features/tools/local_tool_page.dart';
import '../features/tools/more_local_tool_page.dart';
import '../features/postal/postal_code_page.dart';
import '../features/cocktail/cocktail_bar_page.dart';
import '../features/cocktail/cocktail_notes_page.dart';
import '../features/cocktail/cocktail_recipe_page.dart';

/// 路由常量与页面生成
class AppRoutes {
  static const String splash = '/';
  static const String login = '/login';
  static const String home = '/home';
  static const String chatList = '/chat_list';
  static const String chatDetail = '/chat_detail';
  static const String moments = '/moments';
  static const String minecraftServer = '/minecraft_server';
  static const String travelPlanner = '/travel_planner';
  static const String postalCode = '/postal_code';
  static const String cocktailBar = '/cocktail_bar';
  static const String cocktailNotes = '/cocktail_notes';
  static const String cocktailRecipes = '/cocktail_recipes';
  static const String countdown = '/countdown';
  static const String randomWheel = '/random_wheel';
  static const String unitConverter = '/unit_converter';
  static const String passwordGenerator = '/password_generator';
  static const String pomodoro = '/pomodoro';
  static const String whatToEat = '/what_to_eat';
  static const String bmi = '/bmi';
  static const String timestamp = '/timestamp';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case splash:
        return _fadeRoute(const SplashPage());
      case login:
        return _fadeRoute(const LoginPage());
      case home:
        return _fadeRoute(const HomePage());
      case chatList:
        return _fadeRoute(const ChatListPage());
      case chatDetail:
        final rawArgs = settings.arguments;
        final args = rawArgs is Map ? rawArgs : const {};
        return _fadeRoute(ChatDetailPage(
          chatId: args['chatId']?.toString() ?? '',
          chatName: args['chatName']?.toString() ?? '',
          isGroup: args['isGroup'] == true,
          receiverId: args['receiverId'],
        ));
      case moments:
        return _fadeRoute(const MomentsPage());
      case minecraftServer:
        return _fadeRoute(const MinecraftServerPage());
      case travelPlanner:
        return _fadeRoute(const TravelPlannerPage());
      case postalCode:
        return _fadeRoute(const PostalCodePage());
      case cocktailBar:
        return _fadeRoute(const CocktailBarPage());
      case cocktailNotes:
        return _fadeRoute(const CocktailNotesPage());
      case cocktailRecipes:
        return _fadeRoute(const CocktailRecipePage());
      case countdown:
        return _fadeRoute(const LocalToolPage(tool: LocalTool.countdown));
      case randomWheel:
        return _fadeRoute(const LocalToolPage(tool: LocalTool.wheel));
      case unitConverter:
        return _fadeRoute(const LocalToolPage(tool: LocalTool.converter));
      case passwordGenerator:
        return _fadeRoute(const LocalToolPage(tool: LocalTool.password));
      case pomodoro:
        return _fadeRoute(
            const MoreLocalToolPage(tool: MoreLocalTool.pomodoro));
      case whatToEat:
        return _fadeRoute(
            const MoreLocalToolPage(tool: MoreLocalTool.whatToEat));
      case bmi:
        return _fadeRoute(const MoreLocalToolPage(tool: MoreLocalTool.bmi));
      case timestamp:
        return _fadeRoute(
            const MoreLocalToolPage(tool: MoreLocalTool.timestamp));
      default:
        return _fadeRoute(const SplashPage());
    }
  }

  static PageRouteBuilder _fadeRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (_, animation, __) => page,
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 250),
    );
  }
}
