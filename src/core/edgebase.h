#ifndef EDGEBASE_H
#define EDGEBASE_H

#include <QQuickItem>
#include <QPointer>
#include <deque>

#include "neuronifyobject.h"

class NodeBase;
class EdgeEngine;

class EdgeBase : public NeuronifyObject
{
    Q_OBJECT

    Q_PROPERTY(NodeBase* itemA READ itemA WRITE setItemA NOTIFY itemAChanged)
    Q_PROPERTY(NodeBase* itemB READ itemB WRITE setItemB NOTIFY itemBChanged)
    Q_PROPERTY(EdgeEngine* engine READ engine WRITE setEngine NOTIFY engineChanged)
    Q_PROPERTY(bool curved READ curved WRITE setCurved NOTIFY curvedChanged)

    Q_PROPERTY(bool ltpEnabled READ ltpEnabled WRITE setLtpEnabled NOTIFY ltpEnabledChanged)
    Q_PROPERTY(double synapticWeight READ synapticWeight WRITE setSynapticWeight NOTIFY synapticWeightChanged)
    Q_PROPERTY(double baselineWeight READ baselineWeight WRITE setBaselineWeight NOTIFY baselineWeightChanged)
    Q_PROPERTY(double maxWeight READ maxWeight WRITE setMaxWeight NOTIFY maxWeightChanged)
    Q_PROPERTY(double learningRate READ learningRate WRITE setLearningRate NOTIFY learningRateChanged)
    Q_PROPERTY(double detectionWindow READ detectionWindow WRITE setDetectionWindow NOTIFY detectionWindowChanged)
    Q_PROPERTY(int spikeThreshold READ spikeThreshold WRITE setSpikeThreshold NOTIFY spikeThresholdChanged)
    Q_PROPERTY(double forgettingRate READ forgettingRate WRITE setForgettingRate NOTIFY forgettingRateChanged)

public:
    explicit EdgeBase(QQuickItem *parent = 0);

    NodeBase* itemA() const;
    NodeBase* itemB() const;
    bool curved() const;
    EdgeEngine* engine() const;

    bool ltpEnabled() const;
    double synapticWeight() const;
    double baselineWeight() const;
    double maxWeight() const;
    double learningRate() const;
    double detectionWindow() const;
    int spikeThreshold() const;
    double forgettingRate() const;

signals:
    void itemAChanged(NodeBase* arg);
    void itemBChanged(NodeBase* arg);
    void curvedChanged(bool curved);
    void engineChanged(EdgeEngine* engine);
    void ltpEnabledChanged(bool enabled);
    void synapticWeightChanged(double weight);
    void baselineWeightChanged(double weight);
    void maxWeightChanged(double weight);
    void learningRateChanged(double rate);
    void detectionWindowChanged(double window);
    void spikeThresholdChanged(int threshold);
    void forgettingRateChanged(double rate);

public slots:
    void setItemA(NodeBase* arg);
    void setItemB(NodeBase* arg);
    void setCurved(bool curved);
    void setEngine(EdgeEngine* engine);
    void setLtpEnabled(bool enabled);
    void setSynapticWeight(double weight);
    void setBaselineWeight(double weight);
    void setMaxWeight(double weight);
    void setLearningRate(double rate);
    void setDetectionWindow(double window);
    void setSpikeThreshold(int threshold);
    void setForgettingRate(double rate);

private:
    QPointer<NodeBase> m_itemA;
    QPointer<NodeBase> m_itemB;
    bool m_curved = false;
    EdgeEngine* m_engine = nullptr;
    bool m_ltpEnabled = false;
    double m_synapticWeight = 1.0;
    double m_baselineWeight = 1.0;
    double m_maxWeight = 3.0;
    double m_learningRate = 0.1;
    double m_detectionWindow = 1.0;   // seconds; matches the 0.1-5.0 s UI range
    int m_spikeThreshold = 3;
    double m_forgettingRate = 0.2; // 1/s; decay time constant tau = 1/rate (0.2 -> tau = 5 s)

    friend class GraphEngine;
    friend class EdgeEngine;

};

#endif // EDGEBASE_H
