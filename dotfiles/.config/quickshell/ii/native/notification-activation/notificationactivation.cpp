#include "notificationactivation.hpp"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QGuiApplication>
#include <QMetaObject>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTimer>
#include <QVariant>
#include <QWindow>
#include <qguiapplication_platform.h>
#include <cstring>
#include <wayland-client-core.h>

#if QT_CONFIG(wayland)
#include <QtGui/qpa/qplatformwindow_p.h>
#include "xdg-activation-v1-client-protocol.h"
#endif

namespace {

QWindow* windowForSource(QObject* source) {
    if (auto* window = qobject_cast<QWindow*>(source))
        return window;

    if (auto* item = qobject_cast<QQuickItem*>(source))
        return item->window();

    // Also accept a Quickshell proxy window when one is passed directly.
    if (source) {
        const auto backingWindow = source->property("_backingWindow");
        if (auto* object = backingWindow.value<QObject*>())
            return qobject_cast<QWindow*>(object);
    }

    return nullptr;
}

} // namespace

NotificationActivation::NotificationActivation(QObject* parent)
    : QObject(parent) {
    this->initializeWayland();
}

NotificationActivation::~NotificationActivation() {
    this->clearPendingRequests(false);

#if QT_CONFIG(wayland)
    if (this->activation)
        xdg_activation_v1_destroy(this->activation);
    if (this->registry)
        wl_registry_destroy(this->registry);
#endif
}

void NotificationActivation::initializeWayland() {
#if QT_CONFIG(wayland)
    auto* application = qGuiApp
        ? qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>()
        : nullptr;
    auto* display = application ? application->display() : nullptr;
    if (!display || this->registry)
        return;

    static const wl_registry_listener listener {
        .global = &NotificationActivation::registryGlobal,
        .global_remove = &NotificationActivation::registryGlobalRemove,
    };

    // Qt's token helper returns an empty token for Quickshell's layer-shell
    // windows. Bind the protocol directly and make one local startup roundtrip
    // so the first notification click is ready without a fallback path.
    this->registry = wl_display_get_registry(display);
    if (!this->registry) {
        qWarning("NotificationActivation: failed to obtain the Wayland registry");
        return;
    }

    if (wl_registry_add_listener(this->registry, &listener, this) < 0) {
        qWarning("NotificationActivation: failed to listen to the Wayland registry");
        wl_registry_destroy(this->registry);
        this->registry = nullptr;
        return;
    }

    if (wl_display_roundtrip(display) < 0)
        qWarning("NotificationActivation: Wayland registry roundtrip failed");
#endif
}

void NotificationActivation::clearPendingRequests(bool invokeActions) {
#if QT_CONFIG(wayland)
    while (!this->pendingRequests.isEmpty()) {
        auto request = this->pendingRequests.begin();
        auto* activationToken = request.key();
        const auto action = request->action;
        this->pendingRequests.erase(request);

        if (activationToken)
            xdg_activation_token_v1_destroy(activationToken);
        if (invokeActions && action)
            this->queueInvocation(action);
    }
#else
    Q_UNUSED(invokeActions);
#endif
}

void NotificationActivation::completePendingRequest(
    xdg_activation_token_v1* activationToken,
    const QString& token
) {
#if QT_CONFIG(wayland)
    const auto requestIterator = this->pendingRequests.find(activationToken);
    if (requestIterator == this->pendingRequests.end())
        return;

    const auto request = requestIterator.value();
    this->pendingRequests.erase(requestIterator);
    xdg_activation_token_v1_destroy(activationToken);

    if (!request.action)
        return;

    if (!token.isEmpty()) {
        auto message = QDBusMessage::createSignal(
            QStringLiteral("/org/freedesktop/Notifications"),
            QStringLiteral("org.freedesktop.Notifications"),
            QStringLiteral("ActivationToken")
        );
        message << QVariant::fromValue(request.notificationId) << QVariant::fromValue(token);
        if (!QDBusConnection::sessionBus().send(message))
            qWarning("NotificationActivation: failed to send ActivationToken");
    } else {
        qWarning("NotificationActivation: compositor returned an empty activation token");
    }

    this->queueInvocation(request.action);
#else
    Q_UNUSED(activationToken);
    Q_UNUSED(token);
#endif
}

void NotificationActivation::registryGlobal(
    void* data,
    wl_registry* registry,
    quint32 name,
    const char* interface,
    quint32 version
) {
#if QT_CONFIG(wayland)
    auto* self = static_cast<NotificationActivation*>(data);
    if (self->activation || std::strcmp(interface, xdg_activation_v1_interface.name) != 0)
        return;

    self->activationGlobalName = name;
    self->activation = static_cast<xdg_activation_v1*>(wl_registry_bind(
        registry,
        name,
        &xdg_activation_v1_interface,
        qMin(version, 1U)
    ));
#else
    Q_UNUSED(data);
    Q_UNUSED(registry);
    Q_UNUSED(name);
    Q_UNUSED(interface);
    Q_UNUSED(version);
#endif
}

void NotificationActivation::registryGlobalRemove(
    void* data,
    wl_registry* registry,
    quint32 name
) {
    Q_UNUSED(registry);

#if QT_CONFIG(wayland)
    auto* self = static_cast<NotificationActivation*>(data);
    if (name != self->activationGlobalName)
        return;

    if (!self->pendingRequests.isEmpty()) {
        qWarning("NotificationActivation: xdg-activation-v1 disappeared; invoking pending actions without tokens");
        self->clearPendingRequests(true);
    }
    if (self->activation)
        xdg_activation_v1_destroy(self->activation);
    self->activation = nullptr;
    self->activationGlobalName = 0;
#else
    Q_UNUSED(data);
    Q_UNUSED(name);
#endif
}

void NotificationActivation::tokenDone(
    void* data,
    xdg_activation_token_v1* activationToken,
    const char* token
) {
#if QT_CONFIG(wayland)
    auto* self = static_cast<NotificationActivation*>(data);
    self->completePendingRequest(activationToken, QString::fromUtf8(token));
#else
    Q_UNUSED(data);
    Q_UNUSED(activationToken);
    Q_UNUSED(token);
#endif
}

void NotificationActivation::queueInvocation(QObject* action) const {
    const QPointer<QObject> guardedAction(action);
    QTimer::singleShot(0, this, [guardedAction]() {
        if (!guardedAction)
            return;

        if (!QMetaObject::invokeMethod(guardedAction, "invoke", Qt::DirectConnection))
            qWarning("NotificationActivation: action has no invokable invoke() method");
    });
}

bool NotificationActivation::invokeAction(
    quint32 notificationId,
    QObject* action,
    QObject* source
) {
    if (!action || action->metaObject()->indexOfMethod("invoke()") < 0)
        return false;

#if QT_CONFIG(wayland)
    auto* window = windowForSource(source);
    auto* application = qGuiApp
        ? qGuiApp->nativeInterface<QNativeInterface::QWaylandApplication>()
        : nullptr;
    auto* waylandWindow = window
        ? window->nativeInterface<QNativeInterface::Private::QWaylandWindow>()
        : nullptr;
    const auto serial = application ? application->lastInputSerial() : 0;
    auto* seat = application ? application->lastInputSeat() : nullptr;
    auto* surface = waylandWindow ? waylandWindow->surface() : nullptr;

    if (!this->activation)
        this->initializeWayland();

    if (this->activation && surface && seat && serial != 0) {
        auto* activationToken = xdg_activation_v1_get_activation_token(this->activation);
        if (!activationToken) {
            qWarning("NotificationActivation: failed to allocate an activation token request");
            this->queueInvocation(action);
            return true;
        }

        this->pendingRequests.insert(
            activationToken,
            PendingRequest { notificationId, QPointer<QObject>(action) }
        );

        static const xdg_activation_token_v1_listener listener {
            .done = &NotificationActivation::tokenDone,
        };
        xdg_activation_token_v1_add_listener(activationToken, &listener, this);
        xdg_activation_token_v1_set_serial(activationToken, serial, seat);
        xdg_activation_token_v1_set_surface(activationToken, surface);
        xdg_activation_token_v1_commit(activationToken);

        wl_display_flush(application->display());
        return true;
    }

    if (!window)
        qWarning("NotificationActivation: click source has no QQuickWindow");
    else if (!application)
        qWarning("NotificationActivation: Qt is not using its Wayland platform integration");
    else if (!this->activation)
        qWarning("NotificationActivation: compositor does not expose xdg-activation-v1");
    else if (!surface)
        qWarning("NotificationActivation: click window has no Wayland surface");
    else if (!seat)
        qWarning("NotificationActivation: click has no Wayland input seat");
    else
        qWarning("NotificationActivation: click has no Wayland input serial");
#else
    Q_UNUSED(notificationId);
    Q_UNUSED(source);
#endif

    // X11 and headless/non-surface callers retain the existing action path.
    this->queueInvocation(action);
    return true;
}
