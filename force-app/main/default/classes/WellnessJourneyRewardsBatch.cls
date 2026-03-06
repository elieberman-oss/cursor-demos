/**
 * Batch class for Rewards Management challenge.
 * Serializes user details from completed Wellness Journeys and submits them via callout.
 */
global class WellnessJourneyRewardsBatch implements Database.Batchable<sObject>, Database.Stateful, Database.AllowsCallouts {

    // Accumulate user journey counts and details across batches
    private Map<Id, Integer> userGoalCountMap = new Map<Id, Integer>();
    private Map<Id, Map<String, Object>> userDetailsMap = new Map<Id, Map<String, Object>>();

    global Database.QueryLocator start(Database.BatchableContext BC) {
        Date startDate = getStartDate();
        Date endDate = getEndDate();
        String query = 'SELECT Id, OwnerId, Owner.Name, Owner.Email, Owner.Username FROM Wellness_Journey__c WHERE Status__c = \'Complete\' AND Completion_Date__c >= :startDate AND Completion_Date__c <= :endDate ORDER BY OwnerId, Completion_Date__c';
        return Database.getQueryLocator(query);
    }

    global void execute(Database.BatchableContext BC, List<Wellness_Journey__c> scope) {
        for (Wellness_Journey__c journey : scope) {
            Id ownerId = journey.OwnerId;
            // Accumulate count per user
            Integer count = userGoalCountMap.get(ownerId);
            if (count == null) {
                count = 0;
            }
            count++;
            userGoalCountMap.put(ownerId, count);
            // Store user details (overwrite each time; same user data)
            Map<String, Object> userObj = new Map<String, Object>{
                'userId' => journey.OwnerId,
                'fullName' => journey.Owner.Name,
                'email' => journey.Owner.Email,
                'username' => journey.Owner.Username
            };
            userDetailsMap.put(ownerId, userObj);
        }
    }

    global void finish(Database.BatchableContext BC) {
        // Build list of users who completed at least 12 goals in the quarter
        List<Map<String, Object>> usersList = new List<Map<String, Object>>();
        for (Id userId : userGoalCountMap.keySet()) {
            if (userGoalCountMap.get(userId) >= 12 && userDetailsMap.containsKey(userId)) {
                usersList.add(userDetailsMap.get(userId));
            }
        }
        // Serialize user details to JSON
        String jsonBody = JSON.serialize(usersList);
        // Call out to the external rewards system
        Integer responseCode = RewardsCalloutService.submitUsersForRewardCallout(jsonBody);
        System.debug('HTTP Response Code: ' + responseCode);
    }

    private Date getStartDate() {
        Date today = Date.today();
        Integer currentYear = today.year();
        Integer currentMonth = today.month();
        Integer previousQuarterStartMonth = ((currentMonth - 1) / 3) * 3 + 1 - 3;
        if (previousQuarterStartMonth <= 0) {
            previousQuarterStartMonth += 12;
            currentYear--;
        }
        return Date.newInstance(currentYear, previousQuarterStartMonth, 1);
    }

    private Date getEndDate() {
        Date startDate = getStartDate();
        return startDate.addMonths(3).addDays(-1);
    }
}
