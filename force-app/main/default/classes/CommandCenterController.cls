public without sharing class CommandCenterController {

    public class DashboardData {
        @AuraEnabled public List<EscalationCard> openEscalations;
        @AuraEnabled public List<CaseCard> breachedCases;
        @AuraEnabled public List<CaseCard> criticalWatchlist;
        @AuraEnabled public SnapshotData todaySnapshot;
        @AuraEnabled public List<ComplianceData> complianceByPlan;
        @AuraEnabled public List<ComplianceData> complianceBySeverity;
    }

    public class EscalationCard {
        @AuraEnabled public String escalationId;
        @AuraEnabled public String caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String escalationType;
        @AuraEnabled public String escalationStatus;
        @AuraEnabled public String notes;
        @AuraEnabled public DateTime triggeredOn;
        @AuraEnabled public String severity;
        @AuraEnabled public String accountName;
    }

    public class CaseCard {
        @AuraEnabled public String caseId;
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String subject;
        @AuraEnabled public String severity;
        @AuraEnabled public String status;
        @AuraEnabled public String accountName;
        @AuraEnabled public String ownerName;
        @AuraEnabled public DateTime responseDue;
        @AuraEnabled public DateTime resolutionDue;
        @AuraEnabled public Boolean responseBreached;
        @AuraEnabled public Boolean resolutionBreached;
    }

    public class SnapshotData {
        @AuraEnabled public Integer casesCreatedToday;
        @AuraEnabled public Integer casesResolvedToday;
        @AuraEnabled public Integer casesBreachedToday;
        @AuraEnabled public Integer openEscalationCount;
        @AuraEnabled public Integer activeCaseCount;
    }

    public class ComplianceData {
        @AuraEnabled public String groupName;
        @AuraEnabled public Integer totalCases;
        @AuraEnabled public Integer responseMet;
        @AuraEnabled public Integer resolutionMet;
        @AuraEnabled public Decimal responseCompliancePct;
        @AuraEnabled public Decimal resolutionCompliancePct;
    }

    @AuraEnabled(cacheable=false)
    public static DashboardData getDashboardData() {
        DashboardData data = new DashboardData();

        data.openEscalations = getOpenEscalations();
        data.breachedCases = getBreachedCases();
        data.criticalWatchlist = getCriticalWatchlist();
        data.todaySnapshot = getTodaySnapshot();
        data.complianceByPlan = getComplianceByPlan();
        data.complianceBySeverity = getComplianceBySeverity();

        return data;
    }

    private static List<EscalationCard> getOpenEscalations() {
        List<EscalationCard> cards = new List<EscalationCard>();

        for (Escalation__c esc : [
            SELECT Id, Case__c, Case__r.CaseNumber, Case__r.Severity__c,
                   Case__r.Account.Name,
                   Escalation_Type__c, Escalation_Status__c, Notes__c, Triggered_on__c
            FROM Escalation__c
            WHERE Escalation_Status__c IN ('Open', 'In Progress')
            ORDER BY Triggered_on__c DESC
            LIMIT 50
        ]) {
            EscalationCard card = new EscalationCard();
            card.escalationId = esc.Id;
            card.caseId = esc.Case__c;
            card.caseNumber = esc.Case__r.CaseNumber;
            card.escalationType = esc.Escalation_Type__c;
            card.escalationStatus = esc.Escalation_Status__c;
            card.notes = esc.Notes__c;
            card.triggeredOn = esc.Triggered_on__c;
            card.severity = esc.Case__r.Severity__c;
            card.accountName = esc.Case__r.Account.Name;
            cards.add(card);
        }

        return cards;
    }

    private static List<CaseCard> getBreachedCases() {
        List<CaseCard> cards = new List<CaseCard>();
        DateTime now = System.now();

        for (Case c : [
            SELECT Id, CaseNumber, Subject, Severity__c, Status,
                   Account.Name, Owner.Name,
                   Response_Due_on__c, Resolution_due_on__c
            FROM Case
            WHERE Status NOT IN ('Closed', 'Resolved')
            AND Severity__c != null
            AND (Response_Due_on__c < :now OR Resolution_due_on__c < :now)
            ORDER BY Severity__c ASC, Response_Due_on__c ASC
            LIMIT 50
        ]) {
            cards.add(buildCaseCard(c, now));
        }

        return cards;
    }

    private static List<CaseCard> getCriticalWatchlist() {
        List<CaseCard> cards = new List<CaseCard>();
        DateTime now = System.now();

        for (Case c : [
            SELECT Id, CaseNumber, Subject, Severity__c, Status,
                   Account.Name, Owner.Name,
                   Response_Due_on__c, Resolution_due_on__c
            FROM Case
            WHERE Status NOT IN ('Closed', 'Resolved', 'Waiting')
            AND Severity__c IN ('S1', 'S2')
            ORDER BY Response_Due_on__c ASC NULLS LAST
            LIMIT 50
        ]) {
            cards.add(buildCaseCard(c, now));
        }

        return cards;
    }

    private static SnapshotData getTodaySnapshot() {
        SnapshotData snapshot = new SnapshotData();
        DateTime todayStart = DateTime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0));
        DateTime now = System.now();

        snapshot.casesCreatedToday = [
            SELECT COUNT() FROM Case WHERE CreatedDate >= :todayStart
        ];

        snapshot.casesResolvedToday = [
            SELECT COUNT() FROM Case 
            WHERE Status IN ('Closed', 'Resolved') 
            AND ClosedDate >= :todayStart
        ];

        snapshot.casesBreachedToday = [
            SELECT COUNT() FROM Case 
            WHERE Status NOT IN ('Closed', 'Resolved')
            AND Severity__c != null
            AND (Response_Due_on__c < :now OR Resolution_due_on__c < :now)
        ];

        snapshot.openEscalationCount = [
            SELECT COUNT() FROM Escalation__c 
            WHERE Escalation_Status__c IN ('Open', 'In Progress')
        ];

        snapshot.activeCaseCount = [
            SELECT COUNT() FROM Case 
            WHERE Status NOT IN ('Closed', 'Resolved')
            AND Severity__c != null
        ];

        return snapshot;
    }

    /**
     * SLA compliance by Coverage Plan — computed in Apex from Case_Analytics__c.
     */
    private static List<ComplianceData> getComplianceByPlan() {
        List<ComplianceData> result = new List<ComplianceData>();

        // Query all analytics records grouped by plan
        List<Case_Analytics__c> allRecords = [
            SELECT Coverage_Plan__c, Response_Met__c, Resolution_Met__c
            FROM Case_Analytics__c
            WHERE Coverage_Plan__c != null
            ORDER BY Coverage_Plan__c
        ];

        // Group and count in Apex
        Map<String, ComplianceData> planMap = new Map<String, ComplianceData>();

        for (Case_Analytics__c ca : allRecords) {
            String plan = ca.Coverage_Plan__c;

            if (!planMap.containsKey(plan)) {
                ComplianceData cd = new ComplianceData();
                cd.groupName = plan;
                cd.totalCases = 0;
                cd.responseMet = 0;
                cd.resolutionMet = 0;
                planMap.put(plan, cd);
            }

            ComplianceData cd = planMap.get(plan);
            cd.totalCases++;
            if (ca.Response_Met__c) {
                cd.responseMet++;
            }
            if (ca.Resolution_Met__c) {
                cd.resolutionMet++;
            }
        }

        for (ComplianceData cd : planMap.values()) {
            cd.responseCompliancePct = cd.totalCases > 0 
                ? (Decimal)cd.responseMet / cd.totalCases * 100 : 0;
            cd.resolutionCompliancePct = cd.totalCases > 0 
                ? (Decimal)cd.resolutionMet / cd.totalCases * 100 : 0;
            result.add(cd);
        }

        return result;
    }

    /**
     * SLA compliance by Severity — computed in Apex from Case_Analytics__c.
     */
    private static List<ComplianceData> getComplianceBySeverity() {
        List<ComplianceData> result = new List<ComplianceData>();

        List<Case_Analytics__c> allRecords = [
            SELECT Severity__c, Response_Met__c, Resolution_Met__c
            FROM Case_Analytics__c
            WHERE Severity__c != null
            ORDER BY Severity__c
        ];

        Map<String, ComplianceData> sevMap = new Map<String, ComplianceData>();

        for (Case_Analytics__c ca : allRecords) {
            String sev = ca.Severity__c;

            if (!sevMap.containsKey(sev)) {
                ComplianceData cd = new ComplianceData();
                cd.groupName = sev;
                cd.totalCases = 0;
                cd.responseMet = 0;
                cd.resolutionMet = 0;
                sevMap.put(sev, cd);
            }

            ComplianceData cd = sevMap.get(sev);
            cd.totalCases++;
            if (ca.Response_Met__c) {
                cd.responseMet++;
            }
            if (ca.Resolution_Met__c) {
                cd.resolutionMet++;
            }
        }

        for (ComplianceData cd : sevMap.values()) {
            cd.responseCompliancePct = cd.totalCases > 0 
                ? (Decimal)cd.responseMet / cd.totalCases * 100 : 0;
            cd.resolutionCompliancePct = cd.totalCases > 0 
                ? (Decimal)cd.resolutionMet / cd.totalCases * 100 : 0;
            result.add(cd);
        }

        return result;
    }

    private static CaseCard buildCaseCard(Case c, DateTime now) {
        CaseCard card = new CaseCard();
        card.caseId = c.Id;
        card.caseNumber = c.CaseNumber;
        card.subject = c.Subject;
        card.severity = c.Severity__c;
        card.status = c.Status;
        card.accountName = c.Account.Name;
        card.ownerName = c.Owner.Name;
        card.responseDue = c.Response_Due_on__c;
        card.resolutionDue = c.Resolution_due_on__c;
        card.responseBreached = (c.Response_Due_on__c != null && now > c.Response_Due_on__c);
        card.resolutionBreached = (c.Resolution_due_on__c != null && now > c.Resolution_due_on__c);
        return card;
    }
}