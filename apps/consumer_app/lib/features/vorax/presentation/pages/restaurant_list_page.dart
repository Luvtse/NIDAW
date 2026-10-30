import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/restaurant.dart';
import '../bloc/restaurant_bloc.dart';
import '../widgets/restaurant_card.dart';

class RestaurantListPage extends StatefulWidget {
  const RestaurantListPage({super.key});

  @override
  State<RestaurantListPage> createState() => _RestaurantListPageState();
}

class _RestaurantListPageState extends State<RestaurantListPage> {
  final _searchController = TextEditingController();
  String _selectedCategory = 'All';
  String _sortBy = 'Recommended';

  final List<String> _categories = const [
    'All', 'Pizza', 'Sushi', 'Burgers', 'Indian', 'Chinese', 'Mexican', 'Desserts',
  ];
  static const _sortOptions = [
    'Recommended',
    'Highest rated',
    'Fastest delivery',
    'Lowest delivery fee',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<RestaurantBloc>().add(const SearchRestaurants(''));
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showFilters() async {
    final selection = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Sort restaurants',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ..._sortOptions.map(
                (option) => RadioListTile<String>(
                  value: option,
                  groupValue: _sortBy,
                  contentPadding: EdgeInsets.zero,
                  title: Text(option),
                  activeColor: AppColors.primary,
                  onChanged: (value) => Navigator.of(sheetContext).pop(value),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selection != null && mounted) setState(() => _sortBy = selection);
  }

  List<RestaurantSummary> _sorted(List<RestaurantSummary> source) {
    final result = List<RestaurantSummary>.of(source);
    switch (_sortBy) {
      case 'Highest rated':
        result.sort((a, b) => b.rating.compareTo(a.rating));
        break;
      case 'Fastest delivery':
        result.sort((a, b) => a.estimatedDeliveryMinutes.compareTo(b.estimatedDeliveryMinutes));
        break;
      case 'Lowest delivery fee':
        result.sort((a, b) => a.deliveryFee.compareTo(b.deliveryFee));
        break;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Something good is near'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Your food orders',
            onPressed: () => context.push('/vorax/orders'),
            icon: const Icon(Icons.receipt_long_rounded),
          ),
        ],
      ),
      body: BlocBuilder<RestaurantBloc, RestaurantState>(
        builder: (context, state) {
          final restaurants = state is RestaurantLoaded ? _sorted(state.restaurants) : const <RestaurantSummary>[];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search restaurants or cuisines',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _searchController.clear();
                              context.read<RestaurantBloc>().add(const SearchRestaurants(''));
                              setState(() {});
                            },
                          ),
                        IconButton(
                          tooltip: 'Sort restaurants',
                          icon: const Icon(Icons.tune_rounded),
                          onPressed: _showFilters,
                        ),
                      ],
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {});
                    context.read<RestaurantBloc>().add(SearchRestaurants(value));
                  },
                ),
              ),
              SizedBox(
                height: 50,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _categories.length,
                  itemBuilder: (context, index) {
                    final category = _categories[index];
                    final isSelected = category == _selectedCategory;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(category),
                        selected: isSelected,
                        onSelected: (_) {
                          setState(() => _selectedCategory = category);
                          context.read<RestaurantBloc>().add(FilterByCategory(category));
                        },
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : AppColors.textPrimary,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_sortBy != 'Recommended')
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: InputChip(
                      avatar: const Icon(Icons.sort_rounded, size: 16),
                      label: Text(_sortBy),
                      onDeleted: () => setState(() => _sortBy = 'Recommended'),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: state is RestaurantLoaded
                    ? restaurants.isEmpty
                        ? _emptyState(
                            icon: Icons.search_off_rounded,
                            title: 'No restaurants found',
                            message: 'Try another search or cuisine category.',
                            actionLabel: 'Clear search',
                            onAction: () {
                              _searchController.clear();
                              setState(() {
                                _selectedCategory = 'All';
                                _sortBy = 'Recommended';
                              });
                              context.read<RestaurantBloc>().add(const SearchRestaurants(''));
                              context.read<RestaurantBloc>().add(const FilterByCategory('All'));
                            },
                          )
                        : RefreshIndicator(
                            onRefresh: () async {
                              final bloc = context.read<RestaurantBloc>();
                              final refreshFinished = bloc.stream.firstWhere(
                                (nextState) => nextState is RestaurantLoaded || nextState is RestaurantFailure,
                              );
                              bloc.add(const RefreshRestaurants());
                              await refreshFinished;
                            },
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: restaurants.length,
                              itemBuilder: (context, index) {
                                final restaurant = restaurants[index];
                                return RestaurantCard(
                                  restaurant: restaurant,
                                  onTap: () => context.push('/vorax/restaurant/${restaurant.id}/menu'),
                                );
                              },
                            ),
                          )
                    : state is RestaurantLoading
                        ? const Center(child: CircularProgressIndicator())
                        : state is RestaurantFailure
                            ? _emptyState(
                                icon: Icons.cloud_off_rounded,
                                title: 'Restaurants are unavailable',
                                message: state.message,
                                actionLabel: 'Try again',
                                onAction: () => context.read<RestaurantBloc>().add(SearchRestaurants(_searchController.text.trim())),
                              )
                            : _emptyState(
                                icon: Icons.restaurant_menu_rounded,
                                title: 'Find your next favorite',
                                message: 'Search for a restaurant or choose a cuisine to get started.',
                              ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: AppColors.voraxOrange.withOpacity(.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 34, color: AppColors.voraxOrange),
              ),
              const SizedBox(height: 18),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, height: 1.45)),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 18),
                FilledButton(onPressed: onAction, child: Text(actionLabel)),
              ],
            ],
          ),
        ),
      );
}
