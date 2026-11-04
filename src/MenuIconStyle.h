/*
 *   File name: MenuIconStyle.h
 *   Summary:   Reserve icon space for menu items without an icon
 *   License:   GPL V2 - See file LICENSE for details.
 */

#ifndef MenuIconStyle_h
#define MenuIconStyle_h

#include <QMenu>
#include <QPixmap>
#include <QProxyStyle>
#include <QStyleOptionMenuItem>

namespace QDirStat
{
    /**
     * Add transparent menu icons while measuring and painting. Actions can be
     * shared with toolbars, so leave the QAction icons themselves unchanged.
     **/
    class MenuIconStyle: public QProxyStyle
    {
    public:
        explicit MenuIconStyle( QStyle * baseStyle ):
            QProxyStyle( baseStyle )
        {
            const int size = pixelMetric( PM_SmallIconSize );
            QPixmap pixmap( size, size );
            pixmap.fill( Qt::transparent );
            _transparentIcon = QIcon( pixmap );
        }

        void drawControl( ControlElement element, const QStyleOption * option,
                          QPainter * painter, const QWidget * widget = nullptr ) const override
        {
            if ( element == CE_MenuItem )
            {
                if ( const auto * item = menuItemWithoutIcon( option, widget ) )
                {
                    const auto withIcon = addTransparentIcon( *item, widget );
                    QProxyStyle::drawControl( element, &withIcon, painter, widget );
                    return;
                }
            }

            QProxyStyle::drawControl( element, option, painter, widget );
        }

        QSize sizeFromContents( ContentsType type, const QStyleOption * option,
                                const QSize & size, const QWidget * widget ) const override
        {
            if ( type == CT_MenuItem )
            {
                if ( const auto * item = menuItemWithoutIcon( option, widget ) )
                {
                    const auto withIcon = addTransparentIcon( *item, widget );
                    return QProxyStyle::sizeFromContents( type, &withIcon, size, widget );
                }
            }

            return QProxyStyle::sizeFromContents( type, option, size, widget );
        }

    private:
        static const QStyleOptionMenuItem * menuItemWithoutIcon( const QStyleOption * option,
                                                                const QWidget * widget )
        {
            const auto * item = qstyleoption_cast<const QStyleOptionMenuItem *>( option );
            if ( ! item || ! qobject_cast<const QMenu *>( widget ) || ! item->icon.isNull() )
                return nullptr;

            return item->menuItemType == QStyleOptionMenuItem::Normal ||
                   item->menuItemType == QStyleOptionMenuItem::DefaultItem ||
                   item->menuItemType == QStyleOptionMenuItem::SubMenu ? item : nullptr;
        }

        QStyleOptionMenuItem addTransparentIcon( const QStyleOptionMenuItem & item,
                                                const QWidget * widget ) const
        {
            QStyleOptionMenuItem withIcon( item );
            withIcon.icon = _transparentIcon;
            withIcon.maxIconWidth = qMax( item.maxIconWidth,
                                         pixelMetric( PM_SmallIconSize, &item, widget ) );
            return withIcon;
        }

        QIcon _transparentIcon;
    };
}

#endif // MenuIconStyle_h
