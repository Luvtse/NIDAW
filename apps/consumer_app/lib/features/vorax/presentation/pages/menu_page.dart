import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/repositories/restaurant_repository.dart';
import '../../domain/entities/restaurant.dart';

class MenuPage extends StatefulWidget {
  final String restaurantId;
  const MenuPage({super.key, required this.restaurantId});
  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  late Future<List<MenuItem>> _menuFuture;
  final Map<String, int> _cart = {};
  String _selectedCategory = 'All';
  bool _submitting = false;
  String? _error;
  List<MenuItem> _lastLoadedItems = const [];

  @override
  void initState() { super.initState(); _menuFuture = GetIt.I<RestaurantRepository>().getMenu(widget.restaurantId); }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('The menu'),
          actions: [
            IconButton(
              onPressed: _cart.isEmpty ? null : _showCart,
              icon: const Icon(Icons.shopping_cart),
              tooltip: 'View cart',
            ),
          ],
        ),
        body: FutureBuilder<List<MenuItem>>(
          future: _menuFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_rounded, size: 42, color: AppColors.voraxOrange),
                      const SizedBox(height: 12),
                      const Text('Menu could not be loaded.'),
                      TextButton(
                        onPressed: () => setState(() {
                          _menuFuture = GetIt.I<RestaurantRepository>().getMenu(widget.restaurantId);
                        }),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final items = snapshot.data ?? const <MenuItem>[];
            if (snapshot.hasData) _lastLoadedItems = items;
            final availableIds = items
                .where((item) => item.isAvailable)
                .map((item) => item.id)
                .toSet();
            final staleCartIds = _cart.keys
                .where((id) => !availableIds.contains(id))
                .toList(growable: false);
            if (staleCartIds.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() {
                  for (final id in staleCartIds) {
                    _cart.remove(id);
                  }
                  _error = 'Some cart items are no longer available and were removed.';
                });
              });
            }

            final categories = <String>[
              'All',
              ...items
                  .map((item) => item.category)
                  .whereType<String>()
                  .where((value) => value.trim().isNotEmpty)
                  .toSet(),
            ];
            final filtered = items
                .where((item) => item.isAvailable &&
                    (_selectedCategory == 'All' || item.category == _selectedCategory))
                .toList(growable: false);

            return Column(
              children: [
                if (categories.length > 1)
                  SizedBox(
                    height: 58,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(10),
                      children: categories
                          .map((category) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(category),
                                  selected: _selectedCategory == category,
                                  onSelected: (_) => setState(() => _selectedCategory = category),
                                ),
                              ))
                          .toList(growable: false),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Material(
                      color: AppColors.error.withOpacity(.08),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline_rounded, color: AppColors.error),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.error))),
                            IconButton(
                              tooltip: 'Dismiss message',
                              onPressed: () => setState(() => _error = null),
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.restaurant_menu_rounded, size: 42, color: AppColors.voraxOrange),
                                const SizedBox(height: 12),
                                const Text('No dishes in this section', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 6),
                                const Text('Choose another category or check back later.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                                if (_selectedCategory != 'All') ...[
                                  const SizedBox(height: 14),
                                  TextButton(
                                    onPressed: () => setState(() => _selectedCategory = 'All'),
                                    child: const Text('Show all dishes'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) => _menuItemCard(filtered[index], items),
                        ),
                ),
                if (_cart.isNotEmpty) _cartBar(items),
              ],
            );
          },
        ),
      );

  Widget _menuItemCard(MenuItem item, List<MenuItem> allItems) {
    final quantity = _cart[item.id] ?? 0;
    return Card(margin: const EdgeInsets.only(bottom: 12), child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
      ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 84,height: 84,child: item.imageUrl == null || item.imageUrl!.isEmpty ? Container(color: Colors.grey.shade200,child: const Icon(Icons.restaurant_menu)) : Image.network(item.imageUrl!,fit: BoxFit.cover,errorBuilder: (_,__,___)=>Container(color: Colors.grey.shade200,child: const Icon(Icons.restaurant_menu))))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,children: [Text(item.name,style: const TextStyle(fontWeight: FontWeight.bold,fontSize: 16)),if (item.description != null) Text(item.description!,maxLines: 2,overflow: TextOverflow.ellipsis,style: const TextStyle(color: Colors.black54)),const SizedBox(height: 8),Text('${item.currency} ${item.price.toStringAsFixed(2)}',style: const TextStyle(color: AppColors.voraxOrange,fontWeight: FontWeight.bold,fontSize: 16))])),
      if (quantity > 0) Row(mainAxisSize: MainAxisSize.min,children: [IconButton(onPressed: () => setState(() { if (quantity <= 1) { _cart.remove(item.id); } else { _cart[item.id] = quantity - 1; } }),icon: const Icon(Icons.remove_circle_outline)),Text('$quantity'),IconButton(onPressed: () => _addToCart(item, allItems),icon: const Icon(Icons.add_circle_outline))]) else IconButton(onPressed: () => _addToCart(item, allItems),icon: const Icon(Icons.add_circle,color: AppColors.voraxOrange)),
    ])));
  }

  void _addToCart(MenuItem item, List<MenuItem> allItems) {
    final selectedCurrencies = allItems
        .where((candidate) => _cart.containsKey(candidate.id))
        .map((candidate) => candidate.currency.trim().toUpperCase())
        .where((currency) => currency.isNotEmpty)
        .toSet();
    final itemCurrency = item.currency.trim().toUpperCase();
    if (itemCurrency.isEmpty ||
        selectedCurrencies.length > 1 ||
        (selectedCurrencies.isNotEmpty &&
            !selectedCurrencies.contains(itemCurrency))) {
      setState(() {
        _error = 'Items in one order must use the same currency. Remove the existing items before choosing this dish.';
      });
      return;
    }
    setState(() {
      _cart[item.id] = (_cart[item.id] ?? 0) + 1;
      _error = null;
    });
  }

  Widget _cartBar(List<MenuItem> items) {
    final selectedItems = items.where((item) => item.isAvailable && _cart.containsKey(item.id)).toList(growable: false);
    if (selectedItems.isEmpty) return const SizedBox.shrink();
    final total = selectedItems.fold<double>(0, (sum, item) => sum + item.price * _cart[item.id]!);
    final currency = selectedItems.first.currency;
    return SafeArea(child: Container(padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 18, offset: const Offset(0, -4))]),child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,mainAxisSize: MainAxisSize.min,children: [const Text('Estimated subtotal',style: TextStyle(color: Colors.black54)),Text('$currency ${total.toStringAsFixed(2)}',style: const TextStyle(fontSize: 20,fontWeight: FontWeight.bold,color: AppColors.voraxOrange))])),ElevatedButton.icon(onPressed: _submitting ? null : () => _checkout(),icon: _submitting ? const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.shopping_cart_checkout),label: const Text('Checkout'))])));
  }

  Future<void> _showCart() async {
    try {
      final items = await GetIt.I<RestaurantRepository>().getMenu(widget.restaurantId);
      if (!mounted) return;
      final selected = items.where((item) => _cart.containsKey(item.id)).toList(growable: false);
      showModalBottomSheet<void>(context: context,builder: (context) => SafeArea(child: Padding(padding: const EdgeInsets.all(20),child: Column(mainAxisSize: MainAxisSize.min,children: [const Text('Your cart',style: TextStyle(fontSize:20,fontWeight:FontWeight.bold)),...selected.map((item)=>ListTile(title:Text(item.name),subtitle:Text('Quantity: ${_cart[item.id]}'),trailing:Text('${item.currency} ${(item.price*_cart[item.id]!).toStringAsFixed(2)}')))]))));
    } catch (_) {
      if (mounted) setState(() => _error = 'Cart details could not be refreshed. Try again before checkout.');
    }
  }

  Future<void> _checkout() async {
    if (_submitting || _cart.isEmpty) return;
    final addressController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final address = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delivery address'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: addressController,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Enter the full delivery address',
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final normalized = value?.trim() ?? '';
              if (normalized.isEmpty) return 'Enter a delivery address.';
              if (normalized.length < 8) return 'Add more detail to the address.';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, addressController.text.trim());
              }
            },
            child: const Text('Place order'),
          ),
        ],
      ),
    );
    addressController.dispose();
    if (address == null || !mounted) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      // Re-fetch the authoritative menu before checkout so stale availability
      // or prices do not silently become a new order request.
      final latestItems = await GetIt.I<RestaurantRepository>().getMenu(widget.restaurantId);
      final byId = {for (final item in latestItems) item.id: item};
      final unavailable = _cart.keys.any((id) => byId[id] == null || !byId[id]!.isAvailable);
      if (unavailable) {
        if (mounted) {
          setState(() {
            _menuFuture = Future<List<MenuItem>>.value(latestItems);
            _error = 'A selected dish is no longer available. Review your cart and try again.';
          });
        }
        return;
      }
      final previousById = {for (final item in _lastLoadedItems) item.id: item};
      final selectedLatest = _cart.keys.map((id) => byId[id]!).toList(growable: false);
      final latestCurrencies = selectedLatest
          .map((item) => item.currency.trim().toUpperCase())
          .toSet();
      final invalidCurrency = latestCurrencies.contains('') || latestCurrencies.length != 1;
      final changedPriceOrCurrency = _cart.keys.any((id) {
        final previous = previousById[id];
        final latest = byId[id]!;
        return previous != null &&
            (previous.price != latest.price ||
                previous.currency.trim().toUpperCase() != latest.currency.trim().toUpperCase());
      });
      if (invalidCurrency || changedPriceOrCurrency) {
        if (mounted) {
          setState(() {
            _menuFuture = Future<List<MenuItem>>.value(latestItems);
            _error = invalidCurrency
                ? 'The menu currency changed. Review your cart before placing the order.'
                : 'A selected dish price or currency changed. Review the updated menu before placing the order.';
          });
        }
        return;
      }
      final quantities = <String, int>{
        for (final entry in _cart.entries)
          if (entry.value > 0 && byId.containsKey(entry.key)) entry.key: entry.value,
      };
      if (quantities.isEmpty) {
        if (mounted) setState(() => _error = 'Your cart is empty. Add a dish before checkout.');
        return;
      }
      final result = await GetIt.I<RestaurantRepository>().createOrder(
        restaurantId: widget.restaurantId,
        deliveryAddress: address,
        quantities: quantities,
      );
      final orderId = result['id']?.toString();
      if (orderId == null || orderId.isEmpty) {
        throw const FormatException('The server did not return an order id.');
      }
      if (!mounted) return;
      context.go('/vorax/order/$orderId/tracking');
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Order was not placed. Check your connection, sign-in status, menu availability, and delivery address, then try again.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
