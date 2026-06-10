/**
 * Unit tests for NeuraFormScoringEvaluator. Locks in operator semantics so
 * a future safe-AST rewrite of the LWC's conditionalRenderingEvaluator.js
 * can be validated against the same fixtures.
 *
 * Test taxonomy:
 *   - Null / malformed input  ......... 3 cases
 *   - Scalar equals / notEquals  ...... 4 cases
 *   - Numeric comparisons  ............ 4 cases (with the LWC quirk)
 *   - List operators (inList/notInList) 4 cases
 *   - Substring operators  ............ 3 cases
 *   - Logical wrappers (all/any/not) .. 5 cases
 *   - "self" + sibling resources  ..... 3 cases
 *   - Regex  .......................... 2 cases
 *
 *   24 method-level assertions covering ~16 logical branches.
 */
@IsTest
private class NeuraFormScoringEvaluatorTest {

    // ----- null / malformed -------------------------------------------------

    @IsTest
    static void blankCriteriaReturnsNull() {
        System.assertEquals(null,
            NeuraFormScoringEvaluator.evaluate(null, 'Yes', null));
        System.assertEquals(null,
            NeuraFormScoringEvaluator.evaluate('', 'Yes', null));
        System.assertEquals(null,
            NeuraFormScoringEvaluator.evaluate('   ', 'Yes', null));
    }

    @IsTest
    static void malformedJsonReturnsNull() {
        System.assertEquals(null,
            NeuraFormScoringEvaluator.evaluate('{ not valid json', 'Yes', null));
    }

    @IsTest
    static void unknownOperatorReturnsNull() {
        String j = '{"resource":"self","operator":"isMagical","value":"Yes"}';
        System.assertEquals(null,
            NeuraFormScoringEvaluator.evaluate(j, 'Yes', null));
    }

    // ----- scalar equals / notEquals ----------------------------------------

    @IsTest
    static void equalsStringMatch() {
        String j = '{"resource":"self","operator":"equals","value":"Yes"}';
        System.assertEquals(true,
            NeuraFormScoringEvaluator.evaluate(j, 'Yes', null));
    }

    @IsTest
    static void equalsStringMiss() {
        String j = '{"resource":"self","operator":"equals","value":"Yes"}';
        System.assertEquals(false,
            NeuraFormScoringEvaluator.evaluate(j, 'No', null));
    }

    @IsTest
    static void notEqualsTrue() {
        String j = '{"resource":"self","operator":"notEquals","value":"Yes"}';
        System.assertEquals(true,
            NeuraFormScoringEvaluator.evaluate(j, 'No', null));
    }

    @IsTest
    static void equalsNumericBothNumbersCoerced() {
        // answer "5" should equal value 5 (numeric coercion).
        String j = '{"resource":"self","operator":"equals","value":5}';
        System.assertEquals(true,
            NeuraFormScoringEvaluator.evaluate(j, '5', null));
        // And "5.0" vs 5 also numeric-equal.
        System.assertEquals(true,
            NeuraFormScoringEvaluator.evaluate(j, '5.0', null));
    }

    // ----- numeric comparisons (LWC quirk preserved) ------------------------

    @IsTest
    static void lessThanQuirkAnswerGreaterReturnsTrue() {
        // LWC convention: "lessThan" maps to ">"; with answer on the left
        // of the operator, "lessThan 5" against answer 10 evaluates 10 > 5
        // -> true. Mirrored exactly for blob portability.
        String j = '{"resource":"self","operator":"lessThan","value":5}';
        System.assertEquals(true,
            NeuraFormScoringEvaluator.evaluate(j, '10', null));
    }

    @IsTest
    static void greaterThanQuirkAnswerLessReturnsTrue() {
        // "greaterThan 5" against answer 3 -> 3 < 5 -> true (LWC quirk).
        String j = '{"resource":"self","operator":"greaterThan","value":5}';
        System.assertEquals(true,
            NeuraFormScoringEvaluator.evaluate(j, '3', null));
    }

    @IsTest
    static void greaterThanOrEqualBoundaryMatches() {
        String j = '{"resource":"self","operator":"greaterThanOrEqual","value":5}';
        // 5 <= 5 -> true (LWC quirk: greaterThanOrEqual is "<=").
        System.assertEquals(true,
            NeuraFormScoringEvaluator.evaluate(j, '5', null));
    }

    @IsTest
    static void numericComparisonOnNonNumericReturnsNull() {
        String j = '{"resource":"self","operator":"greaterThan","value":5}';
        System.assertEquals(null,
            NeuraFormScoringEvaluator.evaluate(j, 'banana', null));
    }

    // ----- list operators ---------------------------------------------------

    @IsTest
    static void inListMatch() {
        String j = '{"resource":"self","operator":"inList","value":["Yes","Maybe"]}';
        System.assertEquals(true,
            NeuraFormScoringEvaluator.evaluate(j, 'Maybe', null));
    }

    @IsTest
    static void inListMiss() {
        String j = '{"resource":"self","operator":"inList","value":["Yes","Maybe"]}';
        System.assertEquals(false,
            NeuraFormScoringEvaluator.evaluate(j, 'No', null));
    }

    @IsTest
    static void notInListMissReturnsTrue() {
        String j = '{"resource":"self","operator":"notInList","value":["A","B"]}';
        // Negation: membership false -> returned true.
        System.assertEquals(true,
            NeuraFormScoringEvaluator.evaluate(j, 'C', null));
    }

    @IsTest
    static void notInListHitReturnsFalse() {
        String j = '{"resource":"self","operator":"notInList","value":["A","B"]}';
        System.assertEquals(false,
            NeuraFormScoringEvaluator.evaluate(j, 'A', null));
    }

    // ----- substring operators ----------------------------------------------

    @IsTest
    static void containsScalar() {
        String j = '{"resource":"self","operator":"contains","value":"clean"}';
        System.assertEquals(true,
            NeuraFormScoringEvaluator.evaluate(j, 'very clean kitchen', null));
    }

    @IsTest
    static void startsWith() {
        String j = '{"resource":"self","operator":"startsWith","value":"WO-"}';
        System.assertEquals(true,
            NeuraFormScoringEvaluator.evaluate(j, 'WO-12345', null));
    }

    @IsTest
    static void endsWithMiss() {
        String j = '{"resource":"self","operator":"endsWith","value":"-PASS"}';
        System.assertEquals(false,
            NeuraFormScoringEvaluator.evaluate(j, 'WO-12345', null));
    }

    // ----- logical wrappers -------------------------------------------------

    @IsTest
    static void allWrapperAllTrue() {
        String j = '{"all":['
            + '{"resource":"self","operator":"equals","value":"Yes"},'
            + '{"resource":"self","operator":"notEquals","value":"No"}'
            + ']}';
        System.assertEquals(true,
            NeuraFormScoringEvaluator.evaluate(j, 'Yes', null));
    }

    @IsTest
    static void allWrapperOneFalse() {
        String j = '{"all":['
            + '{"resource":"self","operator":"equals","value":"Yes"},'
            + '{"resource":"self","operator":"equals","value":"Maybe"}'
            + ']}';
        System.assertEquals(false,
            NeuraFormScoringEvaluator.evaluate(j, 'Yes', null));
    }

    @IsTest
    static void anyWrapperOneTrue() {
        String j = '{"any":['
            + '{"resource":"self","operator":"equals","value":"Yes"},'
            + '{"resource":"self","operator":"equals","value":"Maybe"}'
            + ']}';
        System.assertEquals(true,
            NeuraFormScoringEvaluator.evaluate(j, 'Maybe', null));
    }

    @IsTest
    static void anyWrapperAllFalse() {
        String j = '{"any":['
            + '{"resource":"self","operator":"equals","value":"A"},'
            + '{"resource":"self","operator":"equals","value":"B"}'
            + ']}';
        System.assertEquals(false,
            NeuraFormScoringEvaluator.evaluate(j, 'C', null));
    }

    @IsTest
    static void notWrapper() {
        String j = '{"not":{"resource":"self","operator":"equals","value":"Yes"}}';
        System.assertEquals(true,
            NeuraFormScoringEvaluator.evaluate(j, 'No', null));
        System.assertEquals(false,
            NeuraFormScoringEvaluator.evaluate(j, 'Yes', null));
    }

    // ----- self + sibling resources ----------------------------------------

    @IsTest
    static void siblingResourceLookup() {
        String j = '{"resource":"q-temperature","operator":"equals","value":"in-range"}';
        Map<String, String> siblings = new Map<String, String>{
            'q-temperature' => 'in-range'
        };
        System.assertEquals(true,
            NeuraFormScoringEvaluator.evaluate(j, 'unrelated', siblings));
    }

    @IsTest
    static void siblingResourceMissingReturnsFalse() {
        // Missing sibling -> answerValue null -> not equal to "yes" -> false.
        String j = '{"resource":"q-missing","operator":"equals","value":"yes"}';
        System.assertEquals(false,
            NeuraFormScoringEvaluator.evaluate(j, 'unrelated', new Map<String, String>()));
    }

    @IsTest
    static void selfDefaultsWhenResourceOmitted() {
        // Leaf missing "resource" entirely should default to self.
        String j = '{"operator":"equals","value":"Yes"}';
        System.assertEquals(true,
            NeuraFormScoringEvaluator.evaluate(j, 'Yes', null));
    }

    // ----- regex ------------------------------------------------------------

    @IsTest
    static void regexMatch() {
        String j = '{"resource":"self","operator":"regex","value":"^WO-[0-9]+$"}';
        System.assertEquals(true,
            NeuraFormScoringEvaluator.evaluate(j, 'WO-12345', null));
    }

    @IsTest
    static void regexInvalidPatternReturnsNull() {
        // Unclosed group -> Pattern.matches throws -> null.
        String j = '{"resource":"self","operator":"regex","value":"["}';
        System.assertEquals(null,
            NeuraFormScoringEvaluator.evaluate(j, 'abc', null));
    }

    // ----- compound real-world case -----------------------------------------

    @IsTest
    static void compoundAllAnyCriticalCase() {
        // Realistic Steritech-style audit criterion:
        //   pass if temperature reading is in range AND no foreign matter
        //   detected, OR if both readings are flagged exception.
        String j = '{"any":['
            + '{"all":['
            + '   {"resource":"q-temp","operator":"equals","value":"in-range"},'
            + '   {"resource":"q-foreign","operator":"equals","value":"none"}'
            + ']},'
            + '{"all":['
            + '   {"resource":"q-temp","operator":"equals","value":"exception"},'
            + '   {"resource":"q-foreign","operator":"equals","value":"exception"}'
            + ']}'
            + ']}';
        Map<String, String> siblings = new Map<String, String>{
            'q-temp' => 'in-range',
            'q-foreign' => 'none'
        };
        System.assertEquals(true,
            NeuraFormScoringEvaluator.evaluate(j, null, siblings));

        siblings.put('q-foreign', 'detected');
        System.assertEquals(false,
            NeuraFormScoringEvaluator.evaluate(j, null, siblings));

        siblings.put('q-temp', 'exception');
        siblings.put('q-foreign', 'exception');
        System.assertEquals(true,
            NeuraFormScoringEvaluator.evaluate(j, null, siblings));
    }

    @isTest
    static void detectsCrossQuestionReferences() {
        System.assertEquals(false, NeuraFormScoringEvaluator.referencesNonSelfResources(null));
        System.assertEquals(false, NeuraFormScoringEvaluator.referencesNonSelfResources('not json'));
        System.assertEquals(false, NeuraFormScoringEvaluator.referencesNonSelfResources(
            '{"all":[{"resource":"self","operator":"equals","value":"pass"}]}'
        ));
        System.assertEquals(true, NeuraFormScoringEvaluator.referencesNonSelfResources(
            '{"all":[{"resource":"self","operator":"equals","value":"pass"},' +
            '{"resource":"OTHER_REF","operator":"equals","value":"yes"}]}'
        ), 'A sibling reference anywhere in the tree counts.');
        System.assertEquals(true, NeuraFormScoringEvaluator.referencesNonSelfResources(
            '{"any":[{"not":{"all":[{"resource":"EXT_1","operator":"isTrue"}]}}]}'
        ), 'Nested all/any/not wrappers are walked.');
    }
}