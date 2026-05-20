public with sharing class NeuraFormLogic {
    private static Integer DATA_URL_CHARACTER_LIMIT = 450000;
    
    public NeuraFormLogic() {

    }

    private static Set<Id> processedTemplates = new Set<Id>();

    public static void deleteFileRecords(List<Form_Answer__c> formAnswerList) {
        List<Id> answerId = new List<Id>();
        
        for(Form_Answer__c answer: formAnswerList) {
            answerId.add(answer.Id);
        }
        
        List<ContentDocumentLink> links = [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId IN :answerId];
        Set<Id> contentDocumentIds = new Set<Id>();

        for (ContentDocumentLink link : links) {
            contentDocumentIds.add(link.ContentDocumentId);
        }

        if (contentDocumentIds.isEmpty()) {
            return;
        }

        delete links;

        delete [SELECT Id FROM ContentDocument WHERE Id IN :contentDocumentIds];
    }
    
    public static void processTemplates(Set<Id> parentIds) {
        // Filter out already processed parent IDs
        Set<Id> unprocessedParentIds = new Set<Id>();
        for (Id parentId : parentIds) {
            if (!processedTemplates.contains(parentId)) {
                unprocessedParentIds.add(parentId);
            }
        }

        if (!unprocessedParentIds.isEmpty()) {
            Map<Id, Form_Template__c> recordMap = new Map<Id, Form_Template__c>([SELECT Id, Pages_JSON__c, Sections_JSON__c, Questions_JSON__c, Questions_JSON_1__c, Questions_JSON_2__c, Page_Conditions__c, Section_Conditions__c, Question_Conditions__c FROM Form_Template__c WHERE Id IN :unprocessedParentIds]);
            updateJSON(recordMap);
            processedTemplates.addAll(unprocessedParentIds);
        }
    }


    public static void updateJSON(Map<Id, Form_Template__c> recordMap){
        Map<Id, FormTemplateWrapper> formTemplateMap = new Map<Id, FormTemplateWrapper>();

        Set<Id> recordIds = recordMap.keySet();
        // query all related form pages
        List<Form_Page__c> formPages = [SELECT Id, Name, Form_Template__c, Order__c, Title__c, Conditions__c  FROM Form_Page__c WHERE Form_Template__c IN :recordIds];
        // query all related form sections
        List<Form_Section__c> formSections = [SELECT Id, Name, Form_Page__c, Order__c, Show_Title__c, Title__c, Background_Color__c, Padding__c, Column_Size__c, Columns__c, Form_Template__c, Conditions__c FROM Form_Section__c WHERE Form_Template__c IN :recordIds];
        // query all related form questions
       
        List<Form_Question__c> formQuestions = [SELECT Id, Name, Form_Section__c, Order__c, Question__c, Label_Visible__c, Text_Alignment__c, Font_Size__c, Font_Color__c, Value_Set__c, Include_Comment__c, Include_Photo__c, Type__c, Form_Template__c,Layout_Item__c,Display_Rich_Text__c, Conditions__c, Active_Message__c, Inactive_Message__c, Required__c, Decimal_Places__c FROM Form_Question__c WHERE Form_Template__c IN :recordIds];

        // Loop over form pages and add the element to the Form Wrapper Map
        for(Form_Page__c page : formPages){
            Boolean hasConditions = page.Conditions__c != null && page.Conditions__c != '' && page.Conditions__c != '{}';
            String conditionsToAdd = '';
            if(hasConditions){
                conditionsToAdd = addIdToJson(page.Conditions__c, page.Id);
            }
            page.Conditions__c = null;

            if(formTemplateMap.containsKey(page.Form_Template__c)){
                // if the page has conditions then add it to the page map
                if(hasConditions){
                    formTemplateMap.get(page.Form_Template__c).pageConditions.add(conditionsToAdd);
                }
                formTemplateMap.get(page.Form_Template__c).pages.add(page);
            } else {
                List<String> pageConditions = new List<String>();
                if(hasConditions){
                    pageConditions.add(conditionsToAdd);
                }

                formTemplateMap.put(page.Form_Template__c, new FormTemplateWrapper(page.Form_Template__c, new List<Form_Page__c>{page}, new List<Form_Section__c>{}, new List<Form_Question__c>{}, pageConditions, new List<String>{}, new List<String>{}));
            }
        }

        // Loop over form sections and add the element to the Form Wrapper Map
        for(Form_Section__c section : formSections){
            Boolean hasConditions = section.Conditions__c != null && section.Conditions__c != '' && section.Conditions__c != '{}';
            String conditionsToAdd = '';
            if(hasConditions){
                conditionsToAdd = addIdToJson(section.Conditions__c, section.Id);
            }
            section.Conditions__c = null;

            if(formTemplateMap.containsKey(section.Form_Template__c)){

                // if the section has conditions then add it to the section map
                if(hasConditions){
                    formTemplateMap.get(section.Form_Template__c).sectionConditions.add(conditionsToAdd);
                }

                formTemplateMap.get(section.Form_Template__c).sections.add(section);
            } else {
                List<String> sectionConditions = new List<String>();
                if(hasConditions){
                    sectionConditions.add(conditionsToAdd);
                }

                formTemplateMap.put(section.Form_Template__c, new FormTemplateWrapper(section.Form_Template__c, new List<Form_Page__c>{}, new List<Form_Section__c>{section}, new List<Form_Question__c>{}, new List<String>{}, sectionConditions, new List<String>{}));
            }
        }

         // Loop over form questions and add the element to the Form Wrapper Map

        for(Form_Question__c question : formQuestions){
            Boolean hasConditions = question.Conditions__c != null && question.Conditions__c != '' && question.Conditions__c != '{}';

            String conditionsToAdd = '';
            if(hasConditions){
                conditionsToAdd = addIdToJson(question.Conditions__c, question.Id);
            }
            question.Conditions__c = null;

            if(formTemplateMap.containsKey(question.Form_Template__c)){

                 // if the question has conditions then add it to the question map
                if(hasConditions){
                    formTemplateMap.get(question.Form_Template__c).questionConditions.add(conditionsToAdd);
                }


                formTemplateMap.get(question.Form_Template__c).questions.add(question);
            } else {

                List<String> questionConditions = new List<String>();

                if(hasConditions){
                    questionConditions.add(conditionsToAdd);
                }

                formTemplateMap.put(question.Form_Template__c, new FormTemplateWrapper(question.Form_Template__c, new List<Form_Page__c>{}, new List<Form_Section__c>{}, new List<Form_Question__c>{question}, new List<String>{}, new List<String>{}, questionConditions));
            }
        }

        // Loop over the Form Wrapper Map and update the JSON field on Form Template
        for(Form_Template__c formTemplate : recordMap.values()){
            if(formTemplateMap.containsKey(formTemplate.Id)){
                formTemplate.Pages_JSON__c = JSON.serialize(formTemplateMap.get(formTemplate.Id).pages);
                formTemplate.Sections_JSON__c = JSON.serialize(formTemplateMap.get(formTemplate.Id).sections);

                // Reset all questions;
                formTemplate.Questions_JSON__c = '[]';
                formTemplate.Questions_JSON_1__c = '[]';
                formTemplate.Questions_JSON_2__c = '[]';
                List<String> questionsStringList = buildJSONStringListFromList(formTemplateMap.get(formTemplate.Id).questions, 131072);
                Integer counter = 0;
                for(String questionString : questionsStringList){
                    if(counter == 0){
                        formTemplate.Questions_JSON__c = questionString;
                    } else if (counter == 1){
                        formTemplate.Questions_JSON_1__c = questionString;
                    } else if (counter == 2){
                        formTemplate.Questions_JSON_2__c = questionString;
                    }
                    counter++;
                }                
                formTemplate.Page_Conditions__c = buildJSONStringFromList(formTemplateMap.get(formTemplate.Id).pageConditions);
                formTemplate.Section_Conditions__c = buildJSONStringFromList(formTemplateMap.get(formTemplate.Id).sectionConditions);
                formTemplate.Question_Conditions__c = buildJSONStringFromList(formTemplateMap.get(formTemplate.Id).questionConditions);
            }
        }

        update recordMap.values();

    }

    public static String buildJSONStringFromList(List<String> jsonStringList){
        return '[' + String.join(jsonStringList, ',') + ']';
    }

    public static List<String> buildJSONStringListFromList(List<Form_Question__c> formQuestionList, Integer maxLength) {
        List<String> result = new List<String>();
        String currentString = '[';
        
        for (Integer i = 0; i < formQuestionList.size(); i++) {
            String jsonString = JSON.serialize(formQuestionList[i]);
            // Check if adding this jsonString will exceed the maxLength
            if (currentString.length() + jsonString.length() + 1 > maxLength) {
                // Close the current JSON array and add to result
                currentString += ']';
                result.add(currentString);
                // Start a new JSON array
                currentString = '[';
            }
            // Add jsonString to currentString
            if (currentString.length() > 1) {
                currentString += ',';
            }
            currentString += jsonString;
        }
        
        // Add the last JSON array if it has any content
        if (currentString.length() > 1) {
            currentString += ']';
            result.add(currentString);
        }
        
        return result;
    }

    public static String addIdToJson(String jsonString, String idValue) {
        // Parse the JSON string into a Map
        Map<String, Object> jsonMap = (Map<String, Object>) JSON.deserializeUntyped(jsonString);

        // Add the 'id' attribute
        jsonMap.put('id', idValue);

        // Serialize the map back to a JSON string
        String updatedJsonString = JSON.serialize(jsonMap);

        return updatedJsonString;
    }
    
    @AuraEnabled
    public static List<Form_Answer__c> saveFormAnswers(List<Form_Answer__c> answersToSave) {
        if (answersToSave == null || answersToSave.isEmpty()) {
            return answersToSave;
        }

        // Enforce FLS on the client-supplied record fields before DML.
        // Split inserts vs. updates because stripInaccessible uses different
        // access types for each.
        List<Form_Answer__c> toInsert = new List<Form_Answer__c>();
        List<Form_Answer__c> toUpdate = new List<Form_Answer__c>();
        for (Form_Answer__c a : answersToSave) {
            if (a.Id == null) {
                toInsert.add(a);
            } else {
                toUpdate.add(a);
            }
        }

        if (!toInsert.isEmpty()) {
            SObjectAccessDecision insertDecision = Security.stripInaccessible(
                AccessType.CREATABLE, toInsert
            );
            insert insertDecision.getRecords();
        }

        if (!toUpdate.isEmpty()) {
            SObjectAccessDecision updateDecision = Security.stripInaccessible(
                AccessType.UPDATABLE, toUpdate
            );
            update updateDecision.getRecords();
        }

        return answersToSave;
    }

    @AuraEnabled
    public static void deleteFormAnswers(List<Form_Answer__c> answersToDelete) {
        if (answersToDelete == null || answersToDelete.isEmpty()) {
            return;
        }

        Set<Id> ids = new Set<Id>();
        for (Form_Answer__c a : answersToDelete) {
            if (a.Id != null) ids.add(a.Id);
        }
        if (ids.isEmpty()) return;

        // Re-query under sharing so the user actually has access to delete these rows;
        // client-supplied SObjects bypass that check.
        List<Form_Answer__c> deletable = [
            SELECT Id FROM Form_Answer__c WHERE Id IN :ids
        ];
        if (!deletable.isEmpty()) {
            delete deletable;
        }
    }
    
    @AuraEnabled
    public static void uploadFilesForAnswerRecords(List<NeuraFileWrapper> linkedEntityToFilesData) {
        List<ContentVersion> cvList = createContentVersions(linkedEntityToFilesData);
        createContentDocumentLink(cvList);
    }
    
    private static List<ContentVersion> createContentVersions(List<NeuraFileWrapper> linkedEntityToFilesData) {
        List<ContentVersion> cvListToInsert = new List<ContentVersion>();
        
        for(NeuraFileWrapper fileWrapper: linkedEntityToFilesData) {
            List<ContentVersion> cvList = new List<ContentVersion>();
            
            for(Object fileData: fileWrapper.filesData) {
                Map<Object, Object> file = (Map<Object, Object>) fileData;
                
                ContentVersion cv = new ContentVersion();
                
                String encodedString = String.valueOf(file.get('data'));
                encodedString = cleanBase64(encodedString);
                
                cv.VersionData = EncodingUtil.base64Decode(encodedString);
                cv.Title = String.valueOf(String.valueOf(file.get('fileName')));
                cv.PathOnClient = String.valueOf(String.valueOf(file.get('fileName')));
                cv.description = String.valueOf(String.valueOf(file.get('description'))) + '--' + fileWrapper.linkedEntityId;
                
                cvList.add(cv);
            }
            cvListToInsert.addAll(cvList);
        }
        
        insert cvListToInsert;
                                                       
       	return cvListToInsert;                                               
    }

    /**
     * Function to clean base64 data by removing the data URI prefix and any whitespace.
     * @param {string} dataUrl - The base64 string.
     * @returns {string} - The cleaned base64 string.
     */
    public static String cleanBase64(String dataUrl) {
        // Use a regular expression to remove the data URI prefix
        
        List<String> subStringDataUrlList = splitString(dataUrl);
        
        String cleanBase64 = '';
        
        for(String url: subStringDataUrlList) {
            String tempUrl = url.replaceAll('^data:[^;]+;base64,', '');
            tempUrl = tempUrl.replaceAll('\\s', '');
            
            cleanBase64 += tempUrl;
        }
        
        return cleanBase64;
    }
    
     private static List<String> splitString(String input) {
        List<String> chunks = new List<String>();
        Integer length = input.length();
        
        for (Integer i = 0; i < length; i += DATA_URL_CHARACTER_LIMIT) {
            String chunk;
            if (i + DATA_URL_CHARACTER_LIMIT > length) {
                chunk = input.substring(i);
            } else {
                chunk = input.substring(i, i + DATA_URL_CHARACTER_LIMIT);
            }
            chunks.add(chunk);
        }
        
        return chunks;
    }
    
    private static void createContentDocumentLink(List<ContentVersion> cvList) {
        String separationString = '--';
        
        List<ContentVersion> cvListToUpdate = new List<ContentVersion>();
        List<ContentDocumentLink> cdlList = new List<ContentDocumentLink>();
        
        for(ContentVersion cv: [SELECT ContentDocumentId, Description FROM ContentVersion WHERE Id IN :cvList]) {
            Integer searchCharIndex = cv.Description.lastIndexOf(separationString);
            String linkedEntityId = cv.Description.substring(searchCharIndex);
            linkedEntityId = linkedEntityId.remove(separationString);
            
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.ContentDocumentId = cv.ContentDocumentId;
            cdl.LinkedEntityId = linkedEntityId;
            // ShareType is either 'V', 'C', or 'I'
            // V = Viewer, C = Collaborator, I = Inferred
            cdl.ShareType = 'V';
            
            cdlList.add(cdl);
            
            cv.Description = cv.Description.remove(separationString + linkedEntityId);
            cvListToUpdate.add(cv);
        }
        
        insert cdlList;
        update cvListToUpdate;
    }

    public class FormTemplateWrapper{
        public Id Id;
        public List<Form_Page__c> pages;
        public List<Form_Section__c> sections;
        public List<Form_Question__c> questions;
        public List<String> pageConditions;
        public List<String> sectionConditions;
        public List<String> questionConditions;

        public FormTemplateWrapper(){

        }

        public FormTemplateWrapper(Id Id, List<Form_Page__c> pages, List<Form_Section__c> sections, List<Form_Question__c> questions, List<String> pageConditions, List<String> sectionConditions, List<String> questionConditions){
            this.Id = Id;
            this.pages = pages;
            this.sections = sections;
            this.questions = questions;
            this.pageConditions = pageConditions;
            this.sectionConditions = sectionConditions;
            this.questionConditions = questionConditions;
        }
    }
    
    public class CustomException extends Exception {
        
    }
}