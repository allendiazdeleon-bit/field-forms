// Imports for Form_Page__c
import FormPageObject from "@salesforce/schema/Form_Page__c";
import Id from '@salesforce/schema/Form_Page__c.Id';
import IsDeleted from '@salesforce/schema/Form_Page__c.IsDeleted';
import Name from '@salesforce/schema/Form_Page__c.Name';
import CreatedDate from '@salesforce/schema/Form_Page__c.CreatedDate';
import CreatedById from '@salesforce/schema/Form_Page__c.CreatedById';
import LastModifiedDate from '@salesforce/schema/Form_Page__c.LastModifiedDate';
import LastModifiedById from '@salesforce/schema/Form_Page__c.LastModifiedById';
import SystemModstamp from '@salesforce/schema/Form_Page__c.SystemModstamp';
import FormTemplate from '@salesforce/schema/Form_Page__c.Form_Template__c';
import Order from '@salesforce/schema/Form_Page__c.Order__c';
import Title from '@salesforce/schema/Form_Page__c.Title__c';
import PageObjectConditions from '@salesforce/schema/Form_Page__c.Conditions__c';
import ExternalReference from '@salesforce/schema/Form_Page__c.External_Reference__c';

// Imports for Form_Template__c
import FormTemplateObject from '@salesforce/schema/Form_Template__c';
import TemplateOwnerId from '@salesforce/schema/Form_Template__c.OwnerId';
import IndicatorType from '@salesforce/schema/Form_Template__c.Indicator_Type__c';
import PagesJSON from '@salesforce/schema/Form_Template__c.Pages_JSON__c';
import QuestionsJSON from '@salesforce/schema/Form_Template__c.Questions_JSON__c';
import QuestionsJSON1 from '@salesforce/schema/Form_Template__c.Questions_JSON_1__c';
import QuestionsJSON2 from '@salesforce/schema/Form_Template__c.Questions_JSON_2__c';
import SectionsJSON from '@salesforce/schema/Form_Template__c.Sections_JSON__c';
import SelectorColor from '@salesforce/schema/Form_Template__c.Selector_Color__c';
import ExternalReferenceTemplate from '@salesforce/schema/Form_Template__c.External_Reference__c';
import PageConditions from '@salesforce/schema/Form_Template__c.Page_Conditions__c';
import SectionConditions from '@salesforce/schema/Form_Template__c.Section_Conditions__c';
import QuestionConditions from '@salesforce/schema/Form_Template__c.Question_Conditions__c';

//import FormTemplatePages from '@salesforce/schema/Form_Template__c.Form_Pages__r';
//import FormTemplateSections from '@salesforce/schema/Form_Template__c.Form_Sections__r';

// Imports for Linked_Form__c
import LinkedFormObject from '@salesforce/schema/Linked_Form__c';
import LinkedFormId from '@salesforce/schema/Linked_Form__c.Id';
import LinkedFormIsDeleted from '@salesforce/schema/Linked_Form__c.IsDeleted';
import LinkedFormName from '@salesforce/schema/Linked_Form__c.Name';
import LinkedFormCreatedDate from '@salesforce/schema/Linked_Form__c.CreatedDate';
import LinkedFormCreatedById from '@salesforce/schema/Linked_Form__c.CreatedById';
import LinkedFormLastModifiedDate from '@salesforce/schema/Linked_Form__c.LastModifiedDate';
import LinkedFormLastModifiedById from '@salesforce/schema/Linked_Form__c.LastModifiedById';
import LinkedFormSystemModstamp from '@salesforce/schema/Linked_Form__c.SystemModstamp';
import CurrentPage from '@salesforce/schema/Linked_Form__c.Current_Page__c';
import ServiceAppointment from '@salesforce/schema/Linked_Form__c.Service_Appointment__c';
import Status from '@salesforce/schema/Linked_Form__c.Status__c';
import WorkOrderLineItem from '@salesforce/schema/Linked_Form__c.Work_Order_Line_Item__c';
import WorkOrder from '@salesforce/schema/Linked_Form__c.Work_Order__c';
import LinkedFormTemplate from '@salesforce/schema/Linked_Form__c.Form_Template__c';
//import FormAnswers from '@salesforce/schema/Linked_Form__c.Form_Answers__r';

// Imports for Form_Answer__c
import AnswerObject from '@salesforce/schema/Form_Answer__c';
import Answer from '@salesforce/schema/Form_Answer__c.Answer__c';
import FormQuestion from '@salesforce/schema/Form_Answer__c.Form_Question__c';
import LinkedFormAnswer from '@salesforce/schema/Form_Answer__c.Linked_Form__c';
import RelatedComment from '@salesforce/schema/Form_Answer__c.Related_Comment__c';
import Type from '@salesforce/schema/Form_Answer__c.Type__c';

// Imports for Form_Section__c
import FormSectionObject from '@salesforce/schema/Form_Section__c';
import BackgroundColor from '@salesforce/schema/Form_Section__c.Background_Color__c';
import ColumnSize from '@salesforce/schema/Form_Section__c.Column_Size__c';
import Columns from '@salesforce/schema/Form_Section__c.Columns__c';
import FormPage from '@salesforce/schema/Form_Section__c.Form_Page__c';
import SectionOrder from '@salesforce/schema/Form_Section__c.Order__c';
import Padding from '@salesforce/schema/Form_Section__c.Padding__c';
import ShowTitle from '@salesforce/schema/Form_Section__c.Show_Title__c';
import TitleAlignment from '@salesforce/schema/Form_Section__c.Title_Alignment__c';
import SectionTitle from '@salesforce/schema/Form_Section__c.Title__c';
import SectionType from '@salesforce/schema/Form_Section__c.Type__c';
import SectionObjectConditions from '@salesforce/schema/Form_Section__c.Conditions__c'; 
import SectionExternalReference from '@salesforce/schema/Form_Section__c.External_Reference__c';
//import FormQuestions from '@salesforce/schema/Form_Section__c.Form_Questions__r';


// Imports for Form_Question__c
import FormQuestionObject from '@salesforce/schema/Form_Question__c';
import FormQuestionId from '@salesforce/schema/Form_Question__c.Id';
import FormQuestionIsDeleted from '@salesforce/schema/Form_Question__c.IsDeleted';
import FormQuestionName from '@salesforce/schema/Form_Question__c.Name';
import FormQuestionCreatedDate from '@salesforce/schema/Form_Question__c.CreatedDate';
import FormQuestionCreatedById from '@salesforce/schema/Form_Question__c.CreatedById';
import FormQuestionLastModifiedDate from '@salesforce/schema/Form_Question__c.LastModifiedDate';
import FormQuestionLastModifiedById from '@salesforce/schema/Form_Question__c.LastModifiedById';
import FormQuestionSystemModstamp from '@salesforce/schema/Form_Question__c.SystemModstamp';
import FormQuestionFormTemplate from '@salesforce/schema/Form_Question__c.Form_Template__c';
import ActiveMessage from '@salesforce/schema/Form_Question__c.Active_Message__c';
import Column from '@salesforce/schema/Form_Question__c.Column__c';
import DateTimeSaveFormat from '@salesforce/schema/Form_Question__c.Date_Time_Save_Format__c';
import FontColor from '@salesforce/schema/Form_Question__c.Font_Color__c';
import FontSize from '@salesforce/schema/Form_Question__c.Font_Size__c';
import FormPageQuestion from '@salesforce/schema/Form_Question__c.Form_Page__c';
import FormSection from '@salesforce/schema/Form_Question__c.Form_Section__c';
import InactiveMessage from '@salesforce/schema/Form_Question__c.Inactive_Message__c';
import IncludeComment from '@salesforce/schema/Form_Question__c.Include_Comment__c';
import IncludePhoto from '@salesforce/schema/Form_Question__c.Include_Photo__c';
import LabelVisible from '@salesforce/schema/Form_Question__c.Label_Visible__c';
import Length from '@salesforce/schema/Form_Question__c.Length__c';
import Max from '@salesforce/schema/Form_Question__c.Max__c';
import Min from '@salesforce/schema/Form_Question__c.Min__c';
import QuestionOrder from '@salesforce/schema/Form_Question__c.Order__c';
import QuestionText from '@salesforce/schema/Form_Question__c.Question__c';
import Required from '@salesforce/schema/Form_Question__c.Required__c';
import SliderSize from '@salesforce/schema/Form_Question__c.Slider_Size__c';
import SliderStep from '@salesforce/schema/Form_Question__c.Slider_Step__c';
import DecimalPlaces from '@salesforce/schema/Form_Question__c.Decimal_Places__c';
import TextAlignment from '@salesforce/schema/Form_Question__c.Text_Alignment__c';
import QuestionType from '@salesforce/schema/Form_Question__c.Type__c';
import ValueSet from '@salesforce/schema/Form_Question__c.Value_Set__c';
import DisplayRichText from '@salesforce/schema/Form_Question__c.Display_Rich_Text__c';
import LayoutItemCheckbox from '@salesforce/schema/Form_Question__c.Layout_Item__c';

import QuestionObjectConditions from '@salesforce/schema/Form_Question__c.Conditions__c';
import ExternalReferenceQuestion from '@salesforce/schema/Form_Question__c.External_Reference__c';

// ERRORS WITH IMPORTING MDT VIA SCHEMA
// Imports for Form_Setting__mdt
//import FormSettingObject from '@salesforce/schema/Form_Setting__mdt';
//import FormSettingId from '@salesforce/schema/Form_Setting__mdt.Id';
//import FormSettingLabel from '@salesforce/schema/Form_Setting__mdt.Label';
//import Icon from '@salesforce/schema/Form_Setting__mdt.Icon__c';
//import DeveloperName from '@salesforce/schema/Form_Setting__mdt.DeveloperName';
//import MasterLabel from '@salesforce/schema/Form_Setting__mdt.MasterLabel';
//import Structure from '@salesforce/schema/Form_Setting__mdt.Structure__c';
//import DisplayLabel from '@salesforce/schema/Form_Setting__mdt.Display_Label__c';
//import SettingOrder from '@salesforce/schema/Form_Setting__mdt.Order__c';


// Imports for Form_Setting_to_Field__mdt
//import FormSettingToFieldObject from '@salesforce/schema/Form_Setting_to_Field__mdt';
//import SettingToFieldMasterLabel from '@salesforce/schema/Form_Setting_to_Field__mdt.MasterLabel';
//import FormSettingLabelRef from '@salesforce/schema/Form_Setting_to_Field__mdt.Form_Setting__r.Label';
//import FormSettingFieldLabel from '@salesforce/schema/Form_Setting_to_Field__mdt.Form_Setting_Field__r.Label';

function getNamespace(fieldApiName) {
    const parts = fieldApiName.split('__');
    if (parts.length === 3) {
        return `${parts[0]}__`;
    }
    return '';
}

const namespace = getNamespace(FormTemplateObject.objectApiName);

export const FIELDS = {
    Form_Page__c: {
        Id,
        IsDeleted,
        Name,
        CreatedDate,
        CreatedById,
        LastModifiedDate,
        LastModifiedById,
        SystemModstamp,
        FormTemplate,
        Order,
        Title,
        ExternalReference,
        Conditions : PageObjectConditions
    },
    Form_Template__c: {
        OwnerId: TemplateOwnerId,
        IsDeleted,
        Name,
        CreatedDate,
        CreatedById,
        LastModifiedDate,
        LastModifiedById,
        SystemModstamp,
        IndicatorType,
        PagesJSON,
        QuestionsJSON,
        QuestionsJSON1,
        QuestionsJSON2,
        SectionsJSON,
        SelectorColor,
        ExternalReferenceTemplate,
        PageConditions,
        SectionConditions,
        QuestionConditions
    },
    Linked_Form__c: {
        Id: LinkedFormId,
        IsDeleted: LinkedFormIsDeleted,
        Name: LinkedFormName,
        CreatedDate: LinkedFormCreatedDate,
        CreatedById: LinkedFormCreatedById,
        LastModifiedDate: LinkedFormLastModifiedDate,
        LastModifiedById: LinkedFormLastModifiedById,
        SystemModstamp: LinkedFormSystemModstamp,
        CurrentPage,
        ServiceAppointment,
        Status,
        WorkOrderLineItem,
        WorkOrder,
        FormTemplate: LinkedFormTemplate
    },
    Form_Answer__c: {
        Id,
        OwnerId: TemplateOwnerId,
        IsDeleted,
        Name,
        CreatedDate,
        CreatedById,
        LastModifiedDate,
        LastModifiedById,
        SystemModstamp,
        Answer,
        FormQuestion,
        LinkedForm: LinkedFormAnswer,
        RelatedComment,
        Type
    },
    Form_Section__c: {
        Id,
        IsDeleted,
        Name,
        CreatedDate,
        CreatedById,
        LastModifiedDate,
        LastModifiedById,
        SystemModstamp,
        FormTemplate,
        BackgroundColor,
        ColumnSize,
        Columns,
        FormPage,
        Order: SectionOrder,
        Padding,
        ShowTitle,
        TitleAlignment,
        Title: SectionTitle,
        Type: SectionType,
        ExternalReference: SectionExternalReference,
        Conditions : SectionObjectConditions
    },
    Form_Setting__mdt: {
        Id: {fieldApiName : 'Id'},
        Label: {fieldApiName : 'Label'},
        DeveloperName : {fieldApiName : 'DeveloperName'},
        MasterLabel : {fieldApiName : 'MasterLabel'},
        Icon : {fieldApiName : `${namespace}Icon__c`},
        Structure : {fieldApiName : `${namespace}Structure__c`},
        DisplayLabel : {fieldApiName : `${namespace}Display_Label__c`},
        Order:  {fieldApiName : `${namespace}Order__c`}
    },
    Form_Setting_to_Field__mdt: {
        MasterLabel: {fieldApiName : 'MasterLabel'},
        FormSettingRef: {fieldApiName : `${namespace}Form_Setting__r`},
        FormSettingFieldRef : {fieldApiName :`${namespace}Form_Setting_Field__r` },
        FormSettingLabel: {fieldApiName : 'Label'},
        FormSettingFieldLabel : {fieldApiName :'Label' }
    },
    Form_Question__c: {
        Id: FormQuestionId,
        IsDeleted: FormQuestionIsDeleted,
        Name: FormQuestionName,
        CreatedDate: FormQuestionCreatedDate,
        CreatedById: FormQuestionCreatedById,
        LastModifiedDate: FormQuestionLastModifiedDate,
        LastModifiedById: FormQuestionLastModifiedById,
        SystemModstamp: FormQuestionSystemModstamp,
        FormTemplate: FormQuestionFormTemplate,
        ActiveMessage,
        Column,
        DateTimeSaveFormat,
        FontColor,
        FontSize,
        FormPage: FormPageQuestion,
        FormSection,
        InactiveMessage,
        IncludeComment,
        IncludePhoto,
        LabelVisible,
        Length,
        Max,
        Min,
        Order: QuestionOrder,
        Question: QuestionText,
        Required,
        SliderSize,
        SliderStep,
        DecimalPlaces,
        TextAlignment,
        Type: QuestionType,
        ValueSet,
        DisplayRichText,
        LayoutItemCheckbox,
        ExternalReference: ExternalReferenceQuestion,
        Conditions : QuestionObjectConditions
    }
};

export const OBJECTS = {
    Form_Page__c: FormPageObject,
    Form_Template__c: FormTemplateObject,
    Linked_Form__c: LinkedFormObject,
    Form_Answer__c: AnswerObject,
    Form_Section__c: FormSectionObject,
    Form_Setting__mdt: {objectApiName :`${namespace}Form_Setting__mdt`},
    Form_Setting_to_Field__mdt: {objectApiName :`${namespace}Form_Setting_to_Field__mdt`},
    Form_Question__c: FormQuestionObject
};