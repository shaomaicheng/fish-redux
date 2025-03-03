import 'package:flutter/widgets.dart' hide Action;

import '../redux/redux.dart';
import 'basic.dart';
import 'lifecycle.dart';

mixin _ExtraMixin {
  Map<String, Object> _extra;
  Map<String, Object> get extra => _extra ??= <String, Object>{};
}

/// Default Context
abstract class LogicContext<T> extends ContextSys<T> with _ExtraMixin {
  final AbstractLogic<T> logic;

  @override
  final Store<Object> store;
  @override
  final DispatchBus bus;
  @override
  final Enhancer<Object> enhancer;

  final Get<T> getState;

  void Function() _forceUpdate;

  BuildContext _buildContext;
  Dispatch _dispatch;
  Dispatch _onEffect;

  LogicContext({
    @required this.logic,
    @required this.store,
    @required BuildContext buildContext,
    @required this.getState,

    /// pageBus
    @required this.bus,
    @required this.enhancer,
  })  : assert(logic != null),
        assert(store != null),
        assert(buildContext != null),
        assert(getState != null),
        assert(bus != null && enhancer != null),
        _buildContext = buildContext {
    ///
    _onEffect = logic.createOnEffect(this, enhancer);

    /// create Dispatch
    _dispatch = logic.createDispatch(
      _onEffect,
      logic.createAfterEffect(
        this,
        enhancer,
      ),
      this,
    );

    /// Register inter-component broadcast
    registerOnDisposed(bus.registerReceiver(_onEffect));
  }

  @override
  void bindForceUpdate(void Function() forceUpdate) {
    assert(_forceUpdate == null);
    _forceUpdate = forceUpdate;
  }

  @override
  BuildContext get context => _buildContext;

  @override
  T get state => getState();

  @override
  dynamic dispatch(Action action) => _dispatch(action);

  @override
  Widget buildComponent(String name) {
    assert(name != null, 'The name must be NotNull for buildComponent.');
    final Dependent<T> dependent = logic.slot(name);
    final Widget result = dependent?.buildComponent(store, getState,
        bus: bus, enhancer: enhancer);
    assert(result != null, 'Could not found component by name "$name."');
    return result ?? Container();
  }

  @override
  void onLifecycle(Action action) {
    assert(_throwIfDisposed());
    _dispatch(action);
  }

  @override
  void dispose() {
    super.dispose();
    _buildContext = null;
    _forceUpdate = null;
  }

  bool _throwIfDisposed() {
    if (isDisposed) {
      throw Exception(
          'Ctx has been disposed which could not been used any more.');
    }
    return true;
  }

  @override
  State<StatefulWidget> get stfState {
    assert(_buildContext is StatefulElement);
    if (_buildContext is StatefulElement) {
      final StatefulElement stfElement = _buildContext;
      return stfElement.state;
    }
    return null;
  }

  @override
  void broadcastEffect(Action action, {bool excluded}) =>
      bus.dispatch(action, excluded: excluded == true ? _onEffect : null);

  @override
  void broadcast(Action action) => bus.broadcast(action);

  @override
  void Function() addObservable(Subscribe observable) {
    final void Function() unsubscribe = observable(() {
      _forceUpdate?.call();
    });
    registerOnDisposed(unsubscribe);
    return unsubscribe;
  }

  @override
  void forceUpdate() => _forceUpdate?.call();

  @override
  void listen({
    bool Function(T, T) isChanged,
    @required void Function() onChange,
  }) {
    assert(onChange != null);
    T oldState;
    registerOnDisposed(
      store.subscribe(
        () => () {
          final T newState = state;
          final bool flag = isChanged == null
              ? !identical(oldState, newState)
              : isChanged(oldState, newState);
          oldState = newState;
          if (flag) {
            onChange();
          }
        },
      ),
    );
  }
}

class ComponentContext<T> extends LogicContext<T> implements ViewUpdater<T> {
  final ViewBuilder<T> view;
  final ShouldUpdate<T> shouldUpdate;
  final String name;
  final Function() markNeedsBuild;
  final ContextSys<Object> sidecarCtx;

  Widget _widgetCache;
  T _latestState;

  ComponentContext({
    @required AbstractComponent<T> logic,
    @required Store<Object> store,
    @required BuildContext buildContext,
    @required Get<T> getState,
    @required this.view,
    @required this.shouldUpdate,
    @required this.name,
    @required this.markNeedsBuild,
    @required this.sidecarCtx,
    @required DispatchBus bus,
    @required Enhancer<Object> enhancer,
  })  : assert(bus != null && enhancer != null),
        super(
          logic: logic,
          store: store,
          buildContext: buildContext,
          getState: getState,
          bus: bus,
          enhancer: enhancer,
        ) {
    _latestState = state;

    sidecarCtx?.setParent(this);
  }

  @override
  void onLifecycle(Action action) {
    super.onLifecycle(action);
    sidecarCtx?.onLifecycle(LifecycleCreator.reassemble());
  }

  @override
  ListAdapter buildAdapter() {
    assert(sidecarCtx != null);
    return logic.adapterDep()?.buildAdapter(sidecarCtx) ??
        const ListAdapter(null, 0);
  }

  @override
  Widget buildWidget() {
    Widget result = _widgetCache;
    if (result == null) {
      result = _widgetCache = view(state, dispatch, this);

      dispatch(LifecycleCreator.build(name));
    }
    return result;
  }

  @override
  void didUpdateWidget() {
    final T now = state;
    if (shouldUpdate(_latestState, now)) {
      _widgetCache = null;
      _latestState = now;
    }
  }

  @override
  void onNotify() {
    final T now = state;
    if (shouldUpdate(_latestState, now)) {
      _widgetCache = null;

      markNeedsBuild();

      _latestState = now;
    }
  }

  @override
  void reassemble() {
    _widgetCache = null;
  }

  @override
  void forceUpdate() {
    _widgetCache = null;

    try {
      markNeedsBuild();
    } catch (e) {
      /// TODO
      /// should try-catch in force mode which is called from outside
    }
  }
}
