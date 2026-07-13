#include "edgebase.h"
#include "edgeengine.h"
#include "nodebase.h"

/*!
 * \class Edge
 * \inmodule Neuronify
 * \ingroup neuronify-core
 * \brief The Edge class is a basic connection between two nodes.
 *
 * When two objects of the NodeBase type are to be connected in the GraphEngine
 * an Edge object is used to hold a reference to the two objects.
 *
 * It is the responsibility of the Edge object to notify the two NodeBase
 * objects about when it has been added or removed.
 *
 */

EdgeBase::EdgeBase(QQuickItem *parent)
    : NeuronifyObject(parent)
{
}
// === NEW LTP GETTER IMPLEMENTATIONS ===
bool EdgeBase::ltpEnabled() const
{
    return m_ltpEnabled;
}

double EdgeBase::synapticWeight() const
{
    return m_synapticWeight;
}

double EdgeBase::baselineWeight() const
{
    return m_baselineWeight;
}

double EdgeBase::maxWeight() const
{
    return m_maxWeight;
}

double EdgeBase::learningRate() const
{
    return m_learningRate;
}

double EdgeBase::detectionWindow() const
{
    return m_detectionWindow;
}

int EdgeBase::spikeThreshold() const
{
    return m_spikeThreshold;
}

double EdgeBase::forgettingRate() const
{
    return m_forgettingRate;
}
NodeBase *EdgeBase::itemA() const
{
    return m_itemA;
}

NodeBase *EdgeBase::itemB() const
{
    return m_itemB;
}

bool EdgeBase::curved() const
{
    return m_curved;
}

EdgeEngine *EdgeBase::engine() const
{
    return m_engine;
}

void EdgeBase::setItemA(NodeBase *arg)
{
    if (m_itemA == arg)
        return;

    NodeBase* previousItemA = m_itemA;
    if(previousItemA) {
        emit previousItemA->edgeRemoved(this);
    }

    m_itemA = arg;

    emit itemAChanged(arg);
}

void EdgeBase::setItemB(NodeBase *arg)
{
    if (m_itemB == arg)
        return;

    NodeBase* previousItemB = m_itemB;
    if(previousItemB) {
        emit previousItemB->edgeRemoved(this);
    }

    m_itemB = arg;

    emit itemBChanged(arg);
}

void EdgeBase::setCurved(bool curved)
{
    if (m_curved == curved)
        return;

    m_curved = curved;
    emit curvedChanged(curved);
}

void EdgeBase::setEngine(EdgeEngine *engine)
{
    if (m_engine == engine)
        return;

    m_engine = engine;
    emit engineChanged(engine);
}
void EdgeBase::setLtpEnabled(bool enabled)
{
    if (m_ltpEnabled == enabled)
        return;
    m_ltpEnabled = enabled;
    emit ltpEnabledChanged(enabled);
}

void EdgeBase::setSynapticWeight(double weight)
{
    if (m_synapticWeight == weight)
        return;
    m_synapticWeight = weight;
    emit synapticWeightChanged(weight);
}

void EdgeBase::setBaselineWeight(double weight)
{
    if (m_baselineWeight == weight)
        return;
    m_baselineWeight = weight;
    emit baselineWeightChanged(weight);
}

void EdgeBase::setMaxWeight(double weight)
{
    if (m_maxWeight == weight)
        return;
    m_maxWeight = weight;
    emit maxWeightChanged(weight);
}

void EdgeBase::setLearningRate(double rate)
{
    if (m_learningRate == rate)
        return;
    m_learningRate = rate;
    emit learningRateChanged(rate);
}

void EdgeBase::setDetectionWindow(double window)
{
    if (m_detectionWindow == window)
        return;
    m_detectionWindow = window;
    emit detectionWindowChanged(window);
}

void EdgeBase::setSpikeThreshold(int threshold)
{
    if (m_spikeThreshold == threshold)
        return;
    m_spikeThreshold = threshold;
    emit spikeThresholdChanged(threshold);
}

void EdgeBase::setForgettingRate(double rate)
{
    if (m_forgettingRate == rate)
        return;
    m_forgettingRate = rate;
    emit forgettingRateChanged(rate);
}
