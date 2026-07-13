#include "edgeengine.h"
#include "nodeengine.h"
#include "edgebase.h"
#include <QDebug>
#include <cmath>

EdgeEngine::EdgeEngine(QQuickItem *parent)
    : NeuronifyObject(parent)
{

}

double EdgeEngine::currentOutput() const
{
    return m_currentOutput;
}

void EdgeEngine::stepEvent(double dt, bool parentEnabled)
{
    if(!parentEnabled) return;

    m_currentTime += dt;

    EdgeBase* edge = getEdgeBase();
    if(edge && edge->ltpEnabled() &&
        edge->synapticWeight() > edge->baselineWeight()) {

        // Passive weight decay (LTD-like "forgetting"): relax the synaptic
        // weight exponentially back toward baseline.
        //   dw/dt = -(w - baseline) * forgettingRate
        // forgettingRate has units 1/s (it is 1/tau). Higher rate = faster
        // forgetting. A rate of 0 disables decay entirely (weight is held).
        // Default 0.2/s corresponds to tau = 5 s (~63% decay in 5 s).
        double rate = edge->forgettingRate();
        if(rate > 0.0) {
            double baseline = edge->baselineWeight();
            double w = edge->synapticWeight();
            double newWeight = baseline + (w - baseline) * std::exp(-rate * dt);

            // Snap to baseline once we're essentially there, so the decay
            // actually terminates instead of asymptoting forever.
            if(newWeight < baseline + 1e-4) {
                newWeight = baseline;
            }

            edge->setSynapticWeight(newWeight);
        }
    }
}


void EdgeEngine::receiveFireEvent(NodeEngine *sender)
{
    Q_UNUSED(sender);

    EdgeBase* edge = getEdgeBase();
    if(!edge) return;
    if(!edge->ltpEnabled()) return;
    if(!isEnabled()) return;

    trackSpikeForLTP(m_currentTime);
}


void EdgeEngine::receiveFire(NodeEngine *sender)
{
    for(EdgeEngine* child : findChildren<EdgeEngine*>()) {
        child->receiveFire(sender);
    }
    receiveFireEvent(sender);
    emit receivedFire(sender);
}

void EdgeEngine::step(double dt, bool parentEnabled)
{
    bool enable = isEnabled() && parentEnabled;
    for(EdgeEngine* child : findChildren<EdgeEngine*>()) {
        child->step(dt, enable);
    }
    stepEvent(dt, enable);
    emit stepped(dt, enable);
}

void EdgeEngine::setCurrentOutput(double currentOutput)
{
    if (m_currentOutput == currentOutput)
        return;

    m_currentOutput = currentOutput;
    emit currentOutputChanged(currentOutput);
}
// === NEW LTP FUNCTIONS ===

EdgeBase* EdgeEngine::getEdgeBase()
{
    // Try visual parent chain first
    QQuickItem* item = parentItem();
    while(item) {
        EdgeBase* edge = qobject_cast<EdgeBase*>(item);
        if(edge) return edge;
        item = item->parentItem();
    }
    // Fall back to QObject parent chain (handles property-assigned engines)
    QObject* obj = parent();
    while(obj) {
        EdgeBase* edge = qobject_cast<EdgeBase*>(obj);
        if(edge) return edge;
        obj = obj->parent();
    }
    return nullptr;
}

void EdgeEngine::trackSpikeForLTP(double currentTime)
{
    EdgeBase* edge = getEdgeBase();
    if(!edge) return;

    // Step 1: Add the new spike to our list
    m_recentSpikeTimes.push_back(currentTime);

    // Step 2: Remove old spikes outside our time window
    while(!m_recentSpikeTimes.empty()) {
        double oldestSpike = m_recentSpikeTimes.front();
        double timeSinceOldest = currentTime - oldestSpike;

        if(timeSinceOldest > edge->detectionWindow()) {
            m_recentSpikeTimes.pop_front();  // Remove expired spike
        } else {
            break;  // Rest are still fresh
        }
    }

    // Step 3: Check if we have enough spikes for LTP!
    if(m_recentSpikeTimes.size() >= (size_t)edge->spikeThreshold()) {
        triggerLTP();
        m_recentSpikeTimes.clear();  // Reset counter

        qDebug() << "LTP triggered! Spike count:" << edge->spikeThreshold();
    }
}

void EdgeEngine::triggerLTP()
{
    EdgeBase* edge = getEdgeBase();
    if(!edge) return;

    // Increase the synaptic weight
    double increase = edge->learningRate() * (edge->maxWeight() - edge->synapticWeight());

    double newWeight = edge->synapticWeight() + increase;
    newWeight = std::min(newWeight, edge->maxWeight());
    edge->setSynapticWeight(newWeight);

    // Don't let it exceed maximum
    if(newWeight > edge->maxWeight()) {
        newWeight = edge->maxWeight();
    }

    edge->setSynapticWeight(newWeight);

    qDebug() << "LTP triggered! New weight:" << newWeight
             << "Max:" << edge->maxWeight();
}
