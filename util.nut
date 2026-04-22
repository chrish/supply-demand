function listContains(haystack, needle) {
    foreach (k, v in haystack) {
        if (v == needle) {
            return true;
        }
    }
    return false;
}

function addUnique(list, value) {
    if (listContains(list, value)) {
        return false;
    }
    list.append(value);
    return true;
}

function canLoad(orderFlags) {
    if (orderFlags == GSOrder.OF_NONE) {
        return true;
    }

    if (orderFlags & (GSOrder.OF_NO_LOAD | GSOrder.OF_NON_STOP_DESTINATION)) {
        return false;
    }

    if (orderFlags & (GSOrder.OF_TRANSFER | GSOrder.OF_UNLOAD)) {
        return false;
    }

    return true;
}

function canUnload(orderFlags) {
    if (orderFlags == GSOrder.OF_NONE) {
        return true;
    }

    if (orderFlags & (GSOrder.OF_NO_UNLOAD | GSOrder.OF_NON_STOP_DESTINATION)) {
        return false;
    }

    return true;
}

function isTransfer(orderFlags) {
    if (orderFlags == GSOrder.OF_NONE) {
        return false;
    }

    if (orderFlags & GSOrder.OF_NON_STOP_DESTINATION) {
        return false;
    }

    if (orderFlags & GSOrder.OF_TRANSFER) {
        return true;
    }

    return false;
}

function isForceUnload(orderFlags) {
    if (orderFlags == GSOrder.OF_NONE) {
        return false;
    }

    if (orderFlags & GSOrder.OF_NON_STOP_DESTINATION) {
        return false;
    }

    if (orderFlags & GSOrder.OF_UNLOAD) {
        return true;
    }

    return false;
}

function formatDate(date) {
    local month = GSDate.GetMonth(date);
    local day = GSDate.GetDayOfMonth(date);
    return GSDate.GetYear(date) + "-" + (month < 10 ? "0" : "") + month + "-" + (day < 10 ? "0" : "") + day;
}

function getStartOfNextMonth(date, increment) {
    local year = GSDate.GetYear(date);
    local month = GSDate.GetMonth(date) + (increment % 12);
    if (increment >= 12) {
        year += increment / 12;
    }

    if (month > 12) {
        month -= 12;
        year++;
    }
    return GSDate.GetDate(year, month, 1);
}

function monthsBetween(startDate, endDate) {
    return 12 * (GSDate.GetYear(endDate) - GSDate.GetYear(startDate)) + (GSDate.GetMonth(endDate) - GSDate.GetMonth(startDate));
}

function dateCompare(a, b) {
    local aYear = GSDate.GetYear(a);
    local bYear = GSDate.GetYear(b);
    if (aYear > bYear) {
        return 1;
    }
    if (aYear < bYear) {
        return -1;
    }
    local aMonth = GSDate.GetMonth(a);
    local bMonth = GSDate.GetMonth(b);
    if (aMonth > bMonth) {
        return 1;
    }
    if (aMonth < bMonth) {
        return -1;
    }

    local aDay = GSDate.GetDayOfMonth(a);
    local bDay = GSDate.GetDayOfMonth(b);
    if (aDay > bDay) {
        return 1;
    }
    if (aDay < bDay) {
        return -1;
    }

    return 0;
}

function logIfBehindSchedule(lastRunDate, currentDate) {
    local monthsBehind = monthsBetween(lastRunDate, currentDate);
    if (monthsBehind > 1) {
        GSLog.Error("Script is running " + monthsBehind + " months behind schedule!");
        GSLog.Error("Current: " + formatDate(currentDate) + " vs Expected: " + formatDate(lastRunDate));
    } else if (monthsBehind > 0) {
        GSLog.Warning("Script is " + monthsBehind + " month behind schedule.");
    }
}

function getTownIdFromIndustryId(industryId) {
    return GSTile.GetClosestTown(GSIndustry.GetLocation(industryId));
}

function getIndustryStations(industryId) {
    local stationCount = GSIndustry.GetAmountOfStationsAround(industryId);
    if (stationCount < 1) {
        return [];
    }

    local industryTile = GSIndustry.GetLocation(industryId);
    local stations = GSStationList(GSStation.STATION_ANY);
    local stationDistances = [];
    foreach (stationId, _ in stations) {
        local distance = GSStation.GetDistanceManhattanToTile(stationId, industryTile);
        stationDistances.append({
            id = stationId,
            distance = distance
        });
    }

    stationDistances.sort(function(a, b) {
        if (a.distance > b.distance) return 1;
        if (a.distance < b.distance) return -1;
        return 0;
    });

    local sortedList = [];
    foreach (entry in stationDistances) {
        local coverageTiles = GSTileList_StationCoverage(entry.id);
        foreach (tile, _ in coverageTiles) {
            if (GSIndustry.GetIndustryID(tile) == industryId) {
                sortedList.append(entry.id);
                if (sortedList.len() >= stationCount) {
                    return sortedList;
                }
                break;
            }
        }
    }
    return sortedList;
}

/**
 * return the towns that are the final destination for this cargo, or the industries that are intermediarys
 */
function stationCargoRecipients(stationId, cargoId) {
    if (!GSCargoList_StationAccepting(stationId).HasItem(cargoId)) {
        return null;
    }

    local acceptingTowns = [];
    local acceptingIndustries = [];
    local nextCargoIds = [];
    local coverageTiles = GSTileList_StationCoverage(stationId);
    foreach (tile, _ in coverageTiles) {
        local industryId = GSIndustry.GetIndustryID(tile);
        if (!GSIndustry.IsValidIndustry(industryId)) {
            continue;
        }
        if (listContains(acceptingIndustries, industryId) || GSIndustry.IsCargoAccepted(industryId, cargoId) != GSIndustry.CAS_ACCEPTED) {
            continue;
        }
        acceptingIndustries.append(industryId);
        addUnique(acceptingTowns, getTownIdFromIndustryId(industryId));
        local industryType = GSIndustry.GetIndustryType(industryId);
        local producedCargos = GSIndustryType.GetProducedCargo(industryType);
        if (producedCargos.Count() < 1) {
            continue;
        }
        foreach (producedCargoId, _ in producedCargos) {
            addUnique(nextCargoIds, producedCargoId);
        }
    }

    foreach (nextCargoId in nextCargoIds) {
        if (nextCargoId == cargoId) {
            nextCargoIds = [];
            break;
        }
    }

    if (nextCargoIds.len() < 1 && acceptingTowns.len() < 1) {
        return {
            townIds = [GSStation.GetNearestTown(stationId)],
            industryIds = acceptingIndustries,
            nextCargoIds = null,
            nextIndustryIds = null,
        };
    }

    if (nextCargoIds.len() < 1) {
        return {
            townIds = acceptingTowns,
            industryIds = acceptingIndustries,
            nextCargoIds = null,
            nextIndustryIds = null
        };
    }

    return {
        townIds = null,
        industryIds = null,
        nextCargoIds = nextCargoIds,
        nextIndustryIds = acceptingIndustries,
    };
}

function findOrigins(currentDate) {
    local origins = [];
    local validOriginIndustryTypes = getValidOriginIndustryTypes();
    local originTownIds = {};
    local originIndustryIds = {};
    foreach (stationId, _ in GSStationList(GSStation.STATION_ANY)) {
        foreach (cargoType, _ in CargoCategory.townCargoTypes) {
            local townId = GSStation.GetNearestTown(stationId);
            local transported = GSTown.GetLastMonthSupplied(townId, cargoType);
            if (transported < 1) {
                continue;
            }

            if (!(townId in originTownIds)) {
                originTownIds[townId] <- {};
            }
            originTownIds[townId][stationId] <- true;
        }

        local coverageTiles = GSTileList_StationCoverage(stationId);
        foreach (tile, _ in coverageTiles) {
            local industryId = GSIndustry.GetIndustryID(tile);
            if (isValidOriginIndustry(industryId, validOriginIndustryTypes)) {
                if (!(industryId in originIndustryIds)) {
                    originIndustryIds[industryId] <- {};
                }
                originIndustryIds[industryId][stationId] <- true;
            }
        }
    }

    foreach (industryId, stationIds in originIndustryIds) {
        local industryType = GSIndustry.GetIndustryType(industryId);
        local cargoTypes = GSIndustryType.GetProducedCargo(industryType);
        foreach (cargoType, _ in cargoTypes) {
            local transported = GSIndustry.GetLastMonthTransported(industryId, cargoType);
            if (transported < 1) {
                continue;
            }

            local acceptingStations = [];
            foreach (stationId, _ in stationIds) {
                if (GSStation.GetCargoRating(stationId, cargoType) < 1) {
                    continue;
                }
                acceptingStations.append(stationId);
            }

            if (!acceptingStations.len()) {
                continue;
            }
            origins.append({
                date = currentDate,
                townId = null,
                industryId = industryId,
                cargoId = cargoType,
                possibleStationIds = acceptingStations,
                originStationIds = [],
                destinationStationIds = [],
                destinationIndustryIds = [],
                destinationTownIds = [],
                destinationCargoIds = [],
            });
        }
    }

    foreach (townId, stationIds in originTownIds) {
        foreach (cargoType, _ in CargoCategory.townCargoTypes) {
            local acceptingStations = [];
            foreach (stationId, _ in stationIds) {
                if (GSStation.GetCargoRating(stationId, cargoType) < 1) {
                    continue;
                }
                acceptingStations.append(stationId);
            }

            if (!acceptingStations.len()) {
                continue;
            }
            origins.append({
                date = currentDate,
                townId = townId,
                industryId = null,
                cargoId = cargoType,
                possibleStationIds = acceptingStations,
                originStationIds = [],
                destinationStationIds = [],
                destinationIndustryIds = [],
                destinationTownIds = [],
                destinationCargoIds = [],
            });
        }
    }
    return origins;
}

 function isValidOriginIndustry(industryId, validOriginIndustryTypes) {
     if (!GSIndustry.IsValidIndustry(industryId)) {
         return false;
     }
     local industryType = GSIndustry.GetIndustryType(industryId);
     local isValid = false;
     foreach (validType in validOriginIndustryTypes) {
         if (validType == industryType) {
             isValid = true;
             break;
         }
     }
     if (!isValid) {
         return false;
     }
     local currentLevel = GSIndustry.GetProductionLevel(industryId);
     if (!GSIndustry.SetProductionLevel(industryId, currentLevel, false, "")) {
         return false;
     }

    // Lock the industry against vanilla production decreases and closures the
    // moment we identify it as a valid origin. Previously this flag was only
    // set inside increaseSupply() *after* a boost, which meant OpenTTD's
    // built-in monthly production re-roll could still drop production on any
    // industry the script hadn't boosted yet.
    GSIndustry.SetControlFlags(
        industryId,
        GSIndustry.INDCTL_NO_PRODUCTION_DECREASE
      | GSIndustry.INDCTL_NO_CLOSURE
      | GSIndustry.INDCTL_EXTERNAL_PROD_LEVEL
    );
     return true;

     
    return true;
}

function getValidOriginIndustryTypes() {
    local validTypes = [];
    foreach (industryType, _ in GSIndustryTypeList()) {
        if (isValidOriginIndustryType(industryType)) {
            validTypes.append(industryType);
        }
    }
    return validTypes;
}

function isValidOriginIndustryType(industryType) {
    if (!GSIndustryType.ProductionCanIncrease(industryType)) {
        return false;
    }

    if (GSIndustryType.IsRawIndustry(industryType)) {
        return true;
    }

    local acceptedCargoIds = GSIndustryType.GetAcceptedCargo(industryType);
    foreach (cargoId, _ in acceptedCargoIds) {
        // exception for oil rigs
        if (GSCargo.HasCargoClass(cargoId, GSCargo.CC_PASSENGERS)) {
            continue;
        }

        // exception for banks (works with IsRawIndustry() above)
        if (GSCargo.HasCargoClass(cargoId, GSCargo.CC_ARMOURED)) {
            continue;
        }

        return false;
    }

    return true;
}

function addTask(taskQueue, origin, hopStationId, cargoId, originStationId) {
    taskQueue.append({
        origin = origin,
        hopStationId = hopStationId,
        cargoId = cargoId,
        originStationId = originStationId,
    });
}

function registerDestination(task, recipients, stationId, companyId) {
    foreach (townId in recipients.townIds) {
        addUnique(task.origin.destinationTownIds, townId);
        if (!recipients.industryIds.len()) {
            CargoTracker.track(task.origin, companyId, task.cargoId, townId, null);
        }
    }

    addUnique(task.origin.originStationIds, task.originStationId);
    addUnique(task.origin.destinationStationIds, stationId);
    addUnique(task.origin.destinationCargoIds, task.cargoId);

    foreach (industryId in recipients.industryIds) {
        addUnique(task.origin.destinationIndustryIds, industryId);
        CargoTracker.track(task.origin, companyId, task.cargoId, null, industryId);
    }
}

class CargoTracker {
    static trackedCargo = {};
    static towns = {};

    static function save() {
        local saveData = {
            trackedCargo = CargoTracker.trackedCargo,
            towns = CargoTracker.towns,
        };
        return saveData;
    }

    static function load(saveData) {
        foreach (key, value in saveData.trackedCargo) {
            CargoTracker.trackedCargo[key] <- value;
        }
        foreach (key, value in saveData.towns) {
            CargoTracker.towns[key] <- value;
        }
    }

    static function track(origin, companyId, cargoId, townId, industryId) {
        if (industryId != null) {
            local key = companyId + "_" + cargoId + "_i" + industryId;
            if (key in CargoTracker.trackedCargo) {
                return CargoTracker.linkOrigin(CargoTracker.trackedCargo[key], origin);
            }
            CargoTracker.trackedCargo[key] <- CargoTracker.buildTrackedCargo(key, companyId, cargoId, null, industryId);
            return CargoTracker.linkOrigin(CargoTracker.trackedCargo[key], origin);
        }

        local key = companyId + "_" + cargoId + "_t" + townId;
        if (key in CargoTracker.trackedCargo) {
            return CargoTracker.linkOrigin(CargoTracker.trackedCargo[key], origin);
        }
        CargoTracker.trackedCargo[key] <- CargoTracker.buildTrackedCargo(key, companyId, cargoId, townId, null);
        return CargoTracker.linkOrigin(CargoTracker.trackedCargo[key], origin);
    }

    static function linkOrigin(trackedCargo, origin) {
        trackedCargo.date = GSDate.GetCurrentDate();
        local key = origin.industryId ? "i" + origin.industryId : "t" + origin.townId;
        trackedCargo.origins[key] <- origin;
        return trackedCargo;
    }

    static function buildTrackedCargo(key, companyId, cargoId, townId, industryId) {
        if (townId == null) {
            townId = getTownIdFromIndustryId(industryId);
        }
        if (!(townId in CargoTracker.towns)) {
            CargoTracker.towns[townId] <- buildTown(townId);
        }
        local town = CargoTracker.towns[townId];
        local params = {
            key = key,
            origins = {},
            companyId = companyId,
            cargoId = cargoId,
            townId = townId,
            industryId = industryId,
            date = GSDate.GetCurrentDate(),
            startDate = GSDate.GetCurrentDate(),
            cargoReceived = 0,
        };
        town.trackedCargoKeys[key] <- 0;
        return params;
    }

    static function update(date) {
        GSLog.Info("Total tracked items: " + CargoTracker.trackedCargo.len());

        local keysToRemove = [];
        local keptCount = 0;
        local removedCount = 0;

        foreach (key, value in CargoTracker.trackedCargo) {
            local keepTracking = value.date >= date;
            if (!keepTracking) {
                keysToRemove.append(key);
                removedCount++;
            } else {
                keptCount++;
            }

            if (value.cargoReceived == 0) {
                value.startDate = GSDate.GetCurrentDate();
            }

            if (value.industryId) {
                value.cargoReceived += GSCargoMonitor.GetIndustryDeliveryAmount(
                    value.companyId,
                    value.cargoId,
                    value.industryId,
                    keepTracking
                );
                continue;
            }

            value.cargoReceived += GSCargoMonitor.GetTownDeliveryAmount(
                value.companyId,
                value.cargoId,
                value.townId,
                keepTracking
            );
        }

        foreach (key in keysToRemove) {
            local trackedCargo = CargoTracker.trackedCargo[key];
            local town = CargoTracker.towns[trackedCargo.townId];
            delete town.trackedCargoKeys[key];
            delete CargoTracker.trackedCargo[key];
        }
    }

    static function processTowns() {
        foreach (town in CargoTracker.towns) {
            processTown(town);
        }
    }
}

function buildTown(townId) {
    return {
        townId = townId,
        trackedCargoKeys = {},
    }
}

function getTownCargoDemand(population) {
    local req = {
        categories = 0,
        target = 100 * SupplyDemand.runIntervalMonths,
        maxGrowth = 20 * SupplyDemand.runIntervalMonths,
    }

    if (population < 2500) {
        return req;
    }

    if (population < 5000) {
        req.categories = 1;
        req.target = 200 * SupplyDemand.runIntervalMonths;
        req.maxGrowth = 40 * SupplyDemand.runIntervalMonths;
        return req;
    }

    req.categories = 2;
    if (population < 10000) {
        req.target = 400 * SupplyDemand.runIntervalMonths;
        req.maxGrowth = 60 * SupplyDemand.runIntervalMonths;
        return req;
    }

    if (population < 50000) {
        req.target = 800 * SupplyDemand.runIntervalMonths;
        req.maxGrowth = 80 * SupplyDemand.runIntervalMonths;
        return req;
    }

    req.maxGrowth = 100 * SupplyDemand.runIntervalMonths;
    if (population < 200000) {
        req.target = 1200 * SupplyDemand.runIntervalMonths;
        return req;
    }

    req.categories = 3;
    req.target = 2400 * SupplyDemand.runIntervalMonths;
    return req;
}

function analyzeTownCargo(townData) {
    local population = GSTown.GetPopulation(townData.townId);
    local demand = getTownCargoDemand(population);
    local analysis = {
        population = population,
        demand = demand,
        totalDeliveryAmount = 0,
        categoryReceived = buildCategoryCargoTable(), // category -> cargoId -> sum
        categoryOrigins = buildCategoryCargoTable(), // category -> key -> true
        originIndustryIds = {}, // cargoId -> industryIds
        categoryTotals = buildCategoryCargoTable(function() {
            return 0
        }),
        cargoTotals = {}, // cargoId -> sum
        cargoStartDates = {}, // cargoId -> date
        companyCargoTotals = {}, // [companyId][cargoId] -> sum,
        categoryScores = {},
    };

    foreach (key, _ in townData.trackedCargoKeys) {
        local trackedCargo = CargoTracker.trackedCargo[key];
        local cargoId = trackedCargo.cargoId;
        local companyId = trackedCargo.companyId;
        local amount = trackedCargo.cargoReceived;
        local category = getCargoCategory(cargoId);
        analysis.categoryOrigins[category][key] <- true;

        if (!(cargoId in analysis.categoryReceived[category])) {
            analysis.categoryReceived[category][cargoId] <- 0;
        }
        if (!(cargoId in analysis.originIndustryIds)) {
            analysis.originIndustryIds[cargoId] <- {};
        }

        analysis.totalDeliveryAmount += amount;
        analysis.categoryReceived[category][cargoId] += amount;
        analysis.categoryTotals[category] += amount;
        foreach (origin in trackedCargo.origins) {
            if (origin.industryId != null) {
                analysis.originIndustryIds[cargoId][origin.industryId] <- true;
            }
        }

        if (!(cargoId in analysis.cargoTotals)) {
            analysis.cargoTotals[cargoId] <- 0;
            analysis.cargoStartDates[cargoId] <- trackedCargo.startDate;
        }
        analysis.cargoTotals[cargoId] += amount;

        if (!(companyId in analysis.companyCargoTotals)) {
            analysis.companyCargoTotals[companyId] <- {};
        }
        if (!(cargoId in analysis.companyCargoTotals[companyId])) {
            analysis.companyCargoTotals[companyId][cargoId] <- 0;
        }
        analysis.companyCargoTotals[companyId][cargoId] += amount;
    }

    foreach (category in CargoCategory.scoreOrder) {
        local score = {
            totalCargo = 0,
            totalCargos = CargoCategory.sets[category].len(),
            fulfilledCargoIds = [],
        }
        analysis.categoryScores[category] <- score;
    }

    foreach (category in CargoCategory.scoreOrder) {
        local score = analysis.categoryScores[category];
        foreach (cargoId, _ in CargoCategory.sets[category]) {
            if (!(cargoId in analysis.cargoTotals) || !analysis.cargoTotals[cargoId]) {
                continue;
            }
            local amount = analysis.cargoTotals[cargoId];
            if (amount >= demand.target) {
                score.totalCargo += amount;
                score.fulfilledCargoIds.append(cargoId);
                setFulfilledOriginCargoTypes(analysis, cargoId);
                continue;
            }
            local monthsSinceFirstDelivery = monthsBetween(analysis.cargoStartDates[cargoId], GSDate.GetCurrentDate());
            if (monthsSinceFirstDelivery < 1) {
                continue;
            }
            increaseSupply(townData, analysis, cargoId, monthsSinceFirstDelivery);
        }
    }

    return analysis;
}

function setFulfilledOriginCargoTypes(analysis, finalCargoId) {
    foreach (industryId, _ in analysis.originIndustryIds[finalCargoId]) {
        foreach (originCargoId, _ in GSCargoList_IndustryProducing(industryId)) {
            local category = getCargoCategory(originCargoId);
            if  (isScoredCargo(originCargoId)) {
                addUnique(analysis.categoryScores[category].fulfilledCargoIds, originCargoId);
            }
        }
    }
}

function processTown(townData) {
    local analysis = analyzeTownCargo(townData);
    local population = analysis.population;
    local demand = analysis.demand;

    local growthSnapshot = {
        population = analysis.population,
        consumedCount = 0,
        numberOfNewHouses = 0,
        totalCargoTypes = 0,
        fulfilledCargoTypes = 0,
    };

    local fulfilledCategories = [];
    foreach (category in analysis.categoryScores) {
        growthSnapshot.fulfilledCargoTypes += category.fulfilledCargoIds.len();
        growthSnapshot.totalCargoTypes += category.totalCargos;
        if (category.fulfilledCargoIds.len() >= category.totalCargos) {
            fulfilledCategories.append(category);
        }
    }

    local essential = analysis.categoryScores[CargoCategory.ESSENTIAL];
    if (demand.categories < 1) {
        growTierZeroTown(growthSnapshot, analysis, townData, fulfilledCategories);
    }
    else if (essential.fulfilledCargoIds.len() < essential.totalCargos || fulfilledCategories.len() < demand.categories) {
        GSTown.SetText(townData.townId, buildGrowthMessage(growthSnapshot, analysis, townData, fulfilledCategories.len()));
        return;
    }
    else {
        growTown(growthSnapshot, analysis, townData, fulfilledCategories);
    }

    if (growthSnapshot.numberOfNewHouses < 1) {
        return;
    }
    local townName = GSTown.GetName(townData.townId);
    GSLog.Info("Growing town: " + townName + " (Pop: " + analysis.population + ") by " + growthSnapshot.numberOfNewHouses + " houses");
    GSTown.ExpandTown(townData.townId, growthSnapshot.numberOfNewHouses);
    GSTown.SetGrowthRate(townData.townId, GSTown.TOWN_GROWTH_NONE);
    GSTown.SetText(townData.townId, buildGrowthMessage(growthSnapshot, analysis, townData, fulfilledCategories.len()));
}

function growTierZeroTown(growthSnapshot, analysis, townData, fulfilledCategories) {
    foreach (category, score in analysis.categoryScores) {
        foreach (cargoId in score.fulfilledCargoIds) {
            resetCargoAmount(townData, cargoId);
        }
    }
    growthSnapshot.numberOfNewHouses = analysis.demand.maxGrowth * growthSnapshot.fulfilledCargoTypes / growthSnapshot.totalCargoTypes;
}

function growTown(growthSnapshot, analysis, townData, fulfilledCategories) {
    foreach (category, score in analysis.categoryScores) {
        growthSnapshot.consumedCount += score.fulfilledCargoIds.len();
        foreach (cargoId in score.fulfilledCargoIds) {
            resetCargoAmount(townData, cargoId);
        }
    }
    growthSnapshot.numberOfNewHouses = analysis.demand.maxGrowth * fulfilledCategories.len() / CargoCategory.getTotalCategories();
}

function increaseSupply(townData, analysis, cargoId, monthsSinceFirstDelivery) {
    if (cargoId in CargoCategory.townCargoTypes) {
        // passengers and mail which increase with town growth
        // there is an edge case with oil rigs which produce passengers
        // oil rigs will only scale based on oil rather than passengers
        return;
    }

    local maxProduction = 128;
    local bestIndustry = null;
    local bestScore = -1;
    local bestProductionLevel = 0;
    foreach (industryId, _ in analysis.originIndustryIds[cargoId]) {
        if (!GSIndustry.IsValidIndustry(industryId)) {
            continue;
        }

        local productionLevel = GSIndustry.GetProductionLevel(industryId);
        if (productionLevel >= maxProduction) {
            continue;
        }

        local transported = 0;
        local total = 0;
        foreach (cargoId, _ in GSCargoList_IndustryProducing(industryId)) {
            if (cargoId in CargoCategory.townCargoTypes) {
                continue;
            }
            transported += GSIndustry.GetLastMonthTransportedPercentage(industryId, cargoId)
            total++;
        }
        transported = transported / total;
        if (transported < 67) {
            continue;
        }
        local growthPotential = maxProduction - productionLevel;
        local score = (transported * growthPotential) / 100;

        if (score > bestScore) {
            bestScore = score;
            bestIndustry = industryId;
            bestProductionLevel = productionLevel;
        }
    }

    if (bestIndustry == null) {
        return;
    }

    local targetDemand = analysis.demand.target / SupplyDemand.runIntervalMonths;
    local amount = analysis.cargoTotals[cargoId] || 0;
    local monthlyAmount = amount / monthsSinceFirstDelivery;
    local shortageFactor = (targetDemand - monthlyAmount) / targetDemand.tofloat();
    local maxIncrease = 2 * SupplyDemand.runIntervalMonths;
    local targetIncrease = max(1, (maxIncrease * shortageFactor).tointeger());
    local newProductionLevel = min(maxProduction, bestProductionLevel + targetIncrease);
    GSIndustry.SetProductionLevel(bestIndustry, newProductionLevel, false, null);

    local townName = GSTown.GetName(townData.townId);
    local industryName = GSIndustry.GetName(bestIndustry);
    local cargoName = GSCargo.GetName(cargoId);
    GSIndustry.SetControlFlags(bestIndustry, GSIndustry.INDCTL_NO_PRODUCTION_DECREASE | GSIndustry.INDCTL_NO_CLOSURE | GSIndustry.INDCTL_EXTERNAL_PROD_LEVEL);
    GSLog.Info("Increased production at " + industryName + " to " + newProductionLevel + " to address shortage of " + cargoName + " at " + townName);
    local message = GSText(GSText.STR_INDUSTRY_SUMMARY);
    message.AddParam(newProductionLevel);
    message.AddParam(cargoName);
    message.AddParam(townName);
    GSIndustry.SetText(bestIndustry, message);

    return bestIndustry;
}

function resetCargoAmount(townData, cargoId) {
    foreach (key, _ in townData.trackedCargoKeys) {
        local trackedCargo = CargoTracker.trackedCargo[key];
        if (trackedCargo.cargoId == cargoId) {
            trackedCargo.cargoReceived = 0;
            trackedCargo.startDate = GSDate.GetCurrentDate();
        }
    }
}

function buildGrowthMessage(growthSnapshot, analysis, townData, fulfilledCategories) {
    local categorizedCargo = buildCategoryCargoTable();
    local message = GSText(GSText.STR_TOWN_SUMMARY);
    message.AddParam(fulfilledCategories + "/" + analysis.demand.categories);
    message.AddParam(analysis.demand.target);
    message.AddParam(growthSnapshot.numberOfNewHouses + "/" + analysis.demand.maxGrowth);

    foreach (category in CargoCategory.scoreOrder) {
        local score = analysis.categoryScores[category];
        local categoryLine = GSText(GSText["STR_TOWN_" + category + "_LINE"]);
        categoryLine.AddParam(score.totalCargo);
        categoryLine.AddParam(analysis.categoryOrigins[category].len());
        local cargoList = "";
        foreach (cargoId, _ in CargoCategory.sets[category]) {
            if (!listContains(analysis.categoryScores[category].fulfilledCargoIds, cargoId)) {
                continue;
            }
            local amount = cargoId in analysis.cargoTotals ? analysis.cargoTotals[cargoId] : 0;
            cargoList += cargoList != "" ? ", " : "";
            if (amount > 1) {
                cargoList += GSCargo.GetName(cargoId) + ": " + amount;
            }
            else {
                cargoList += GSCargo.GetName(cargoId);
            }
        }
        categoryLine.AddParam(score.fulfilledCargoIds.len() + "/" + score.totalCargos + (cargoList != "" ? " - " + cargoList : ""));
        message.AddParam(categoryLine);
    }
    return message;
}
