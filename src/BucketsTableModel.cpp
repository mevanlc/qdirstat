/*
 *   File name: BucketsTableModel.h
 *   Summary:	Data model for buckets table
 *   License:	GPL V2 - See file LICENSE for details.
 *
 *   Author:	Stefan Hundhammer <Stefan.Hundhammer@gmx.de>
 */


#include "BucketsTableModel.h"
#include "HistogramView.h"
#include "FormatUtil.h"
#include "Logger.h"
#include "Exception.h"

using namespace QDirStat;


BucketsTableModel::BucketsTableModel( QWidget * parent, HistogramView * histogram ):
    QAbstractTableModel( parent ),
    _histogram( histogram )
{
    reset();
}


BucketsTableModel::~BucketsTableModel()
{
    // logDebug() << "destroying" << endl;
}


void BucketsTableModel::reset()
{
    QVector<Bucket> buckets;
    const int count = _histogram->bucketCount();
    buckets.reserve( count );

    for ( int row = 0; row < count; ++row )
    {
        buckets.append( { _histogram->bucketStart( row ),
                          _histogram->bucketEnd( row ),
                          _histogram->bucket( row ) } );
    }

    beginResetModel();
    _buckets.swap( buckets );
    endResetModel();
}


int BucketsTableModel::rowCount( const QModelIndex & parent ) const
{
    return parent.isValid() ? 0 : _buckets.size();
}


int BucketsTableModel::columnCount( const QModelIndex & parent ) const
{
    Q_UNUSED( parent );

    return ColCount;
}


QVariant BucketsTableModel::data( const QModelIndex & index, int role ) const
{
    if ( ! index.isValid() )
	return QVariant();

    switch ( role )
    {
	case Qt::DisplayRole:
	    {
                int row = index.row();

                if ( row < 0 || row >= _buckets.size() )
                    return QVariant();

                const Bucket & bucket = _buckets.at( row );
                QString result;

                switch ( index.column() )
                {
                    case StartCol:  result = formatSize( bucket.start ); break;
                    case EndCol:    result = formatSize( bucket.end ); break;
                    case ValueCol:  result = QString::number( bucket.count ); break;

                    default:        return QVariant();
                }

                return " " + result + " "; // Maintain some margin
	    }

	case Qt::TextAlignmentRole:
            return (int) Qt::AlignVCenter | Qt::AlignRight;

	default:
	    return QVariant();
    }

    /*NOTREACHED*/
    return QVariant();
}


QVariant BucketsTableModel::headerData( int	        section,
                                        Qt::Orientation orientation,
                                        int	        role ) const
{
    switch ( role )
    {
	case Qt::DisplayRole:
            if ( orientation == Qt::Horizontal )
            {
                QString result;

                switch ( section )
                {
                    case StartCol:	result = tr( "Start"         ); break;
                    case EndCol:	result = tr( "End"           ); break;
                    case ValueCol:	result = tr( "Files"         ); break;

                    default: return QVariant();
                }

                return " " + result + " "; // Maintain some margin
            }
            else
            {
                if ( section < _buckets.size() )
                    return " " + QString::number( section + 1 ) + " ";
                else
                    return QVariant();
            }

	case Qt::TextAlignmentRole:
            {
                if ( orientation == Qt::Horizontal )
                    return (int) Qt::AlignVCenter | Qt::AlignHCenter;
                else
                    return (int) Qt::AlignVCenter | Qt::AlignRight;
            }

	default:
	    return QVariant();
    }
}
