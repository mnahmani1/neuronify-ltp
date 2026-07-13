#ifndef EDGEENGINE_H
#define EDGEENGINE_H

#include <QQuickItem>
#include <deque>
#include "neuronifyobject.h"

class NodeEngine;
class EdgeBase;  // Forward declaration is fine here

class EdgeEngine : public NeuronifyObject
{
    Q_OBJECT
    Q_PROPERTY(double currentOutput READ currentOutput WRITE setCurrentOutput NOTIFY currentOutputChanged)

public:
    explicit EdgeEngine(QQuickItem *parent = 0);
    double currentOutput() const;

signals:
    void stepped(double dt, bool parentEnabled);
    void currentOutputChanged(double currentOutput);
    void receivedFire(NodeEngine *sender);

public slots:
    void step(double dt, bool parentEnabled);
    void setCurrentOutput(double currentOutput);
    void receiveFire(NodeEngine *sender);

protected:
    virtual void stepEvent(double dt, bool parentEnabled);
    virtual void receiveFireEvent(NodeEngine *sender);

    // === NEW LTP FUNCTIONS ===
    void trackSpikeForLTP(double currentTime);
    void triggerLTP();
    EdgeBase* getEdgeBase();  // Helper to access EdgeBase properties

private:
    double m_currentOutput = 0.;

    // === NEW LTP TRACKING ===
    std::deque<double> m_recentSpikeTimes;
    double m_currentTime = 0.0;  // Track simulation time
};

#endif // EDGEENGINE_H
