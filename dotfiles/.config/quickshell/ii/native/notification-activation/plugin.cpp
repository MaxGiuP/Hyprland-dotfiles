#include "notificationactivation.hpp"

#include <QJSEngine>
#include <QQmlEngine>
#include <QQmlExtensionPlugin>
#include <qqml.h>

class NotificationActivationPlugin final : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)

public:
    void registerTypes(const char* uri) override {
        Q_ASSERT(QLatin1StringView(uri) == QLatin1StringView("Linmax.NotificationActivation"));
        qmlRegisterSingletonType<NotificationActivation>(
            uri,
            1,
            0,
            "NotificationActivator",
            [](QQmlEngine*, QJSEngine*) -> QObject* {
                return new NotificationActivation;
            }
        );
    }
};

#include "plugin.moc"
