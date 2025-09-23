//
//  Meter.swift
//  LBSwiftUtilities
//
//  Created by Elie Melki on 18/09/2025.
//


actor Meter {
    private(set) var inFlight = 0
    private(set) var peak = 0
    private(set) var started: [Int] = []
    private(set) var finished: [Int] = []

    func start(_ id: Int) {
        inFlight += 1
        if inFlight > peak { peak = inFlight }
        started.append(id)
    }

    func end(_ id: Int) {
        inFlight -= 1
        finished.append(id)
    }

    func snapshot() -> (peak: Int, started: [Int], finished: [Int]) {
        (peak, started, finished)
    }
}

