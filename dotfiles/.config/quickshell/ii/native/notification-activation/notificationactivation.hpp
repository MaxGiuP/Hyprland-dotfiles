#pragma once

#include <QHash>
#include <QObject>
#include <QPointer>

struct wl_registry;
struct xdg_activation_token_v1;
struct xdg_activation_v1;

class NotificationActivation final : public QObject {
    Q_OBJECT

public:
    explicit NotificationActivation(QObject* parent = nullptr);
    ~NotificationActivation() override;

    // Requests a token from the surface that received the click, then invokes
    // the original Quickshell NotificationAction. Returns false only when the
    // supplied action cannot be invoked.
    Q_INVOKABLE bool invokeAction(quint32 notificationId, QObject* action, QObject* source);

private:
    struct PendingRequest {
        quint32 notificationId = 0;
        QPointer<QObject> action;
    };

    void initializeWayland();
    void clearPendingRequests(bool invokeActions);
    void completePendingRequest(xdg_activation_token_v1* activationToken, const QString& token);
    void queueInvocation(QObject* action) const;

    static void registryGlobal(
        void* data,
        wl_registry* registry,
        quint32 name,
        const char* interface,
        quint32 version
    );
    static void registryGlobalRemove(void* data, wl_registry* registry, quint32 name);
    static void tokenDone(
        void* data,
        xdg_activation_token_v1* activationToken,
        const char* token
    );

    quint32 activationGlobalName = 0;
    wl_registry* registry = nullptr;
    xdg_activation_v1* activation = nullptr;
    QHash<xdg_activation_token_v1*, PendingRequest> pendingRequests;
};
