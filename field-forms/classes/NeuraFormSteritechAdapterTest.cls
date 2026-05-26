/**
 * Coverage for NeuraFormSteritechAdapter — verifies the four moving
 * parts of the Steritech transform:
 *
 *   1. Shape detection (canHandle)
 *   2. Page bucketing by line_item_code prefix
 *   3. Catalog dedupe by question_id (the asset/binding split)
 *   4. Recursive child_question flattening with cumulative conditions
 *   5. Type inference warnings
 *   6. Null-named question path-through
 *
 * Fixtures are built inline (~5-10 line items) rather than loaded from
 * the real 1.5 MB steritech.json — that file is too large for a unit
 * test heap budget. The synthetic fixtures exercise the same shape
 * (numeric + letter prefixes, nested child_question chains up to 3
 * levels deep, repeated question_ids across sections, options with
 * null question_name placeholders).
 */
@isTest
private class NeuraFormSteritechAdapterTest {

    @isTest
    static void label_isStable() {
        NeuraFormSteritechAdapter a = new NeuraFormSteritechAdapter();
        System.assertEquals('Steritech Audit Format', a.label(),
            'Adapter label is the stable registry identifier');
    }

    @isTest
    static void canHandle_recognizesSteritechShape() {
        NeuraFormSteritechAdapter a = new NeuraFormSteritechAdapter();
        String good = buildSampleSteritech();
        Decimal score = a.canHandle(good);
        System.assert(score >= 0.85, 'Steritech shape should score >= 0.85 (got ' + score + ')');
    }

    @isTest
    static void canHandle_rejectsOtherShapes() {
        NeuraFormSteritechAdapter a = new NeuraFormSteritechAdapter();
        System.assertEquals(0, a.canHandle(null), 'null source → 0');
        System.assertEquals(0, a.canHandle(''), 'empty source → 0');
        System.assertEquals(0, a.canHandle('{"template":{}}'),
            'Object root (Field Forms shape) → 0');
        System.assertEquals(0, a.canHandle('[{"template":{}}]'),
            'Array of templates (Field Forms shape) → 0');
    }

    @isTest
    static void canHandle_acceptsWithoutPolicy() {
        // Some real-world line items omit the policy field; we should
        // still recognize the payload, just at a slightly lower score.
        NeuraFormSteritechAdapter a = new NeuraFormSteritechAdapter();
        String src = '[{"line_item_code":"700","line_item_title":"x","questions":[]}]';
        Decimal score = a.canHandle(src);
        System.assert(score >= 0.8, 'Missing policy still recognized (got ' + score + ')');
    }

    @isTest
    static void parse_throwsOnEmptySource() {
        NeuraFormSteritechAdapter a = new NeuraFormSteritechAdapter();
        try {
            a.parse('', null);
            System.assert(false, 'Should have thrown for empty source');
        } catch (NeuraFormImporter.AdapterException e) {
            System.assert(e.getMessage().contains('Empty'), e.getMessage());
        }
    }

    @isTest
    static void parse_throwsOnInvalidJson() {
        NeuraFormSteritechAdapter a = new NeuraFormSteritechAdapter();
        try {
            a.parse('not-json', null);
            System.assert(false);
        } catch (NeuraFormImporter.AdapterException e) {
            System.assert(e.getMessage().contains('Could not parse')
                || e.getMessage().contains('top-level JSON array'),
                e.getMessage());
        }
    }

    @isTest
    static void parse_throwsOnObjectRoot() {
        NeuraFormSteritechAdapter a = new NeuraFormSteritechAdapter();
        try {
            a.parse('{"line_item_code":"x"}', null);
            System.assert(false);
        } catch (NeuraFormImporter.AdapterException e) {
            System.assert(e.getMessage().contains('top-level JSON array'),
                e.getMessage());
        }
    }

    @isTest
    static void parse_throwsOnEmptyArray() {
        NeuraFormSteritechAdapter a = new NeuraFormSteritechAdapter();
        try {
            a.parse('[]', null);
            System.assert(false);
        } catch (NeuraFormImporter.AdapterException e) {
            System.assert(e.getMessage().contains('No line items'), e.getMessage());
        }
    }

    @isTest
    static void parse_emitsPagesGroupedByPrefix() {
        NeuraFormSteritechAdapter a = new NeuraFormSteritechAdapter();
        // Three line items spanning two prefixes ('7' numeric and 'A')
        String src = JSON.serialize(new List<Object>{
            buildLineItem('700', 'Pest', 'Policy 700', new List<Object>{
                buildLeafQuestion('qid-1', 'What did you observe?')
            }),
            buildLineItem('701', 'Health', 'Policy 701', new List<Object>{
                buildLeafQuestion('qid-2', 'Enter the date of inspection.')
            }),
            buildLineItem('A101', 'Cold holding', 'Policy A101', new List<Object>{
                buildLeafQuestion('qid-3', 'Briefly describe the issue.')
            })
        });

        NeuraFormIR ir = a.parse(src, null);
        System.assertEquals(2, ir.pages.size(),
            '700/701 share prefix 7; A101 is its own → 2 pages');
        Set<String> pageRefs = new Set<String>();
        for (NeuraFormIR.IRPage p : ir.pages) pageRefs.add(p.external_ref);
        System.assert(pageRefs.contains('steritech_page_7'),
            'numeric codes bucket under 7');
        System.assert(pageRefs.contains('steritech_page_A'),
            'A-prefix codes bucket under A');
    }

    @isTest
    static void parse_emitsOneSectionPerLineItem() {
        NeuraFormSteritechAdapter a = new NeuraFormSteritechAdapter();
        String src = JSON.serialize(new List<Object>{
            buildLineItem('A101', 'Cold holding', 'P1', new List<Object>{
                buildLeafQuestion('q1', 'Leaf?')
            }),
            buildLineItem('A103', 'Hot holding', 'P2', new List<Object>{
                buildLeafQuestion('q2', 'Leaf?')
            }),
            buildLineItem('B205', 'Time', 'P3', new List<Object>{
                buildLeafQuestion('q3', 'Leaf?')
            })
        });
        NeuraFormIR ir = a.parse(src, null);
        System.assertEquals(3, ir.sections.size(), '3 line items → 3 sections');
        // policy_text lands on Form_Section__c.Policy_Text__c
        for (NeuraFormIR.Section s : ir.sections) {
            System.assert(String.isNotBlank(s.policy_text),
                'section.policy_text populated from line_item.policy');
        }
        // Sections share their page when they share a prefix; section.page_ref
        // is the synthesized page external_ref.
        Set<String> pageRefs = new Set<String>();
        for (NeuraFormIR.Section s : ir.sections) pageRefs.add(s.page_ref);
        System.assertEquals(2, pageRefs.size(),
            'A-prefix sections share one page; B-prefix gets its own → 2 page_refs');
    }

    @isTest
    static void parse_emitsCatalogPerUniqueQuestionId() {
        // Same qid appears in two sections; expect ONE catalog entry,
        // TWO bindings.
        NeuraFormSteritechAdapter a = new NeuraFormSteritechAdapter();
        String src = JSON.serialize(new List<Object>{
            buildLineItem('A101', 'Cold', 'P', new List<Object>{
                buildLeafQuestion('shared-qid', 'Reused question?')
            }),
            buildLineItem('A103', 'Hot', 'P', new List<Object>{
                buildLeafQuestion('shared-qid', 'Reused question?')
            })
        });
        NeuraFormIR ir = a.parse(src, null);
        System.assertEquals(1, ir.catalog_entries.size(),
            'One unique qid → one catalog entry (dedupe)');
        System.assertEquals(2, ir.bindings.size(),
            'Same qid in two sections → two bindings');
        for (NeuraFormIR.Binding b : ir.bindings) {
            System.assertEquals('steritech_catalog_shared-qid', b.catalog_ref,
                'Both bindings reference the one catalog entry');
        }
        // Binding external_refs disambiguate by section + qid + n
        System.assertNotEquals(ir.bindings[0].external_ref,
            ir.bindings[1].external_ref,
            'Bindings have unique external_refs even when they share a qid');
    }

    @isTest
    static void parse_emitsBindingPerInstance() {
        NeuraFormSteritechAdapter a = new NeuraFormSteritechAdapter();
        // Three different qids in one section → 3 bindings, 3 catalog
        String src = JSON.serialize(new List<Object>{
            buildLineItem('A101', 'Cold', 'P', new List<Object>{
                buildLeafQuestion('q-1', 'First?'),
                buildLeafQuestion('q-2', 'Second?'),
                buildLeafQuestion('q-3', 'Third?')
            })
        });
        NeuraFormIR ir = a.parse(src, null);
        System.assertEquals(3, ir.catalog_entries.size());
        System.assertEquals(3, ir.bindings.size());
        for (Integer i = 0; i < ir.bindings.size(); i++) {
            System.assertEquals(i + 1, ir.bindings[i].order,
                'Binding order increments within section');
        }
    }

    @isTest
    static void parse_flattensNestedChildQuestions() {
        // Three levels deep: parent → option → child → option → grandchild
        Map<String, Object> grandchild = buildLeafQuestion('g', 'Grandchild leaf?');
        Map<String, Object> child = buildBranchQuestion('c', 'Child branch?',
            new List<Map<String, Object>>{
                option('Yes', grandchild)
            });
        Map<String, Object> parent = buildBranchQuestion('p', 'Parent branch?',
            new List<Map<String, Object>>{
                option('Affirm', child),
                option('Deny', null) // no child — terminates that arm
            });
        String src = JSON.serialize(new List<Object>{
            buildLineItem('A101', 'Section', 'Policy',
                new List<Object>{ parent })
        });
        NeuraFormSteritechAdapter a = new NeuraFormSteritechAdapter();
        NeuraFormIR ir = a.parse(src, null);

        // 3 unique qids → 3 catalog
        System.assertEquals(3, ir.catalog_entries.size());
        // 3 bindings (parent + child + grandchild), all in one section
        System.assertEquals(3, ir.bindings.size());

        // Parent has no conditions; child has 1; grandchild has 2 (AND chain)
        Map<String, NeuraFormIR.Binding> byCatalog =
            new Map<String, NeuraFormIR.Binding>();
        for (NeuraFormIR.Binding b : ir.bindings) {
            byCatalog.put(b.catalog_ref, b);
        }
        NeuraFormIR.Binding parentB = byCatalog.get('steritech_catalog_p');
        NeuraFormIR.Binding childB = byCatalog.get('steritech_catalog_c');
        NeuraFormIR.Binding grandB = byCatalog.get('steritech_catalog_g');

        System.assert(parentB.conditions == null || parentB.conditions.isEmpty(),
            'Top-level question has no conditions');
        System.assertEquals(1, childB.conditions.size(),
            'Child has the parent option as a single condition');
        System.assertEquals('steritech_catalog_p', childB.conditions[0].resource);
        System.assertEquals('equals', childB.conditions[0].operator);
        System.assertEquals('Affirm', childB.conditions[0].value);

        System.assertEquals(2, grandB.conditions.size(),
            'Grandchild carries both ancestor option conditions (AND chain)');
        System.assertEquals('steritech_catalog_p', grandB.conditions[0].resource);
        System.assertEquals('Affirm', grandB.conditions[0].value);
        System.assertEquals('steritech_catalog_c', grandB.conditions[1].resource);
        System.assertEquals('Yes', grandB.conditions[1].value);
    }

    @isTest
    static void parse_inferenceWarning_emittedPerTypeGuess() {
        NeuraFormSteritechAdapter a = new NeuraFormSteritechAdapter();
        String src = JSON.serialize(new List<Object>{
            buildLineItem('A101', 'Section', 'Policy', new List<Object>{
                buildLeafQuestion('q-date', 'Enter the date of inspection.'),
                buildLeafQuestion('q-desc', 'Briefly describe what you saw.'),
                buildLeafQuestion('q-text', 'Enter the name of the manager.')
            })
        });
        NeuraFormIR ir = a.parse(src, null);
        // Catalog types
        Map<String, String> typeByQid = new Map<String, String>();
        for (NeuraFormIR.CatalogEntry c : ir.catalog_entries) {
            typeByQid.put(c.external_ref, c.type);
        }
        System.assertEquals('Date', typeByQid.get('steritech_catalog_q-date'));
        System.assertEquals('Text Area', typeByQid.get('steritech_catalog_q-desc'));
        System.assertEquals('Text', typeByQid.get('steritech_catalog_q-text'));

        // Warnings emitted (one per inferred catalog entry)
        List<String> warns = a.getWarnings();
        Integer inferenceWarnings = 0;
        for (String w : warns) {
            if (w.startsWith('Type inferred:')) inferenceWarnings += 1;
        }
        System.assertEquals(3, inferenceWarnings,
            'One inference warning per catalog entry created');
    }

    @isTest
    static void parse_handlesNullQuestionName() {
        // Placeholder branch: a node with null question_name whose
        // child_question is real. The placeholder should not produce a
        // catalog entry or a binding, but the grandchild should appear
        // and its condition should reference the closest real ancestor.
        Map<String, Object> grandchild = buildLeafQuestion(
            'real-g', 'Real grandchild?');
        Map<String, Object> placeholder = new Map<String, Object>{
            'question_id' => 'placeholder-q',
            'question_name' => null,
            'options' => new List<Object>{
                option('PathOption', grandchild)
            }
        };
        Map<String, Object> parent = buildBranchQuestion('real-p',
            'Real parent?',
            new List<Map<String, Object>>{
                option('Trigger', placeholder)
            });
        String src = JSON.serialize(new List<Object>{
            buildLineItem('A101', 'Section', 'Policy',
                new List<Object>{ parent })
        });

        NeuraFormSteritechAdapter a = new NeuraFormSteritechAdapter();
        NeuraFormIR ir = a.parse(src, null);

        // 2 catalog (parent + grandchild; placeholder skipped)
        System.assertEquals(2, ir.catalog_entries.size(),
            'Placeholder qid does not produce a catalog entry');
        // 2 bindings (parent + grandchild)
        System.assertEquals(2, ir.bindings.size());

        // Grandchild's condition should reference real-p (path-through),
        // not the placeholder.
        for (NeuraFormIR.Binding b : ir.bindings) {
            if (b.catalog_ref == 'steritech_catalog_real-g') {
                System.assertEquals(2, b.conditions.size(),
                    'Grandchild carries the option-chain through the placeholder');
                // First condition is the real parent; second uses the
                // placeholder's option_name but its resource is the
                // closest real ancestor (real-p) — that's the contract.
                System.assertEquals('steritech_catalog_real-p',
                    b.conditions[0].resource);
                System.assertEquals('Trigger', b.conditions[0].value);
                System.assertEquals('steritech_catalog_real-p',
                    b.conditions[1].resource,
                    'Placeholder passes through — condition resource stays on the closest real ancestor');
                System.assertEquals('PathOption', b.conditions[1].value);
            }
        }
    }

    @isTest
    static void parse_optionsBuildValueSet() {
        NeuraFormSteritechAdapter a = new NeuraFormSteritechAdapter();
        Map<String, Object> branch = buildBranchQuestion('mcq',
            'Pick one?',
            new List<Map<String, Object>>{
                option('A', null), option('B', null), option('C', null)
            });
        String src = JSON.serialize(new List<Object>{
            buildLineItem('A101', 'Section', 'Policy',
                new List<Object>{ branch })
        });
        NeuraFormIR ir = a.parse(src, null);
        System.assertEquals(1, ir.catalog_entries.size());
        NeuraFormIR.CatalogEntry c = ir.catalog_entries[0];
        System.assertEquals('Multiple Choice', c.type);
        System.assert(c.value_set != null && c.value_set.contains('A')
            && c.value_set.contains('B') && c.value_set.contains('C'),
            'value_set carries all option names');
    }

    @isTest
    static void parse_endToEnd_steritechSample() {
        NeuraFormSteritechAdapter a = new NeuraFormSteritechAdapter();
        String src = buildSampleSteritech();
        NeuraFormIR ir = a.parse(src, null);

        System.assertEquals('1.0', ir.ir_version);
        System.assertNotEquals(null, ir.template);
        System.assertEquals('steritech_audit_template', ir.template.external_ref);
        // Sample exercises 4 line items spanning 3 prefix buckets (700, A, B)
        System.assertEquals(4, ir.sections.size(), '4 sections');
        System.assertEquals(3, ir.pages.size(), '3 prefix buckets');

        // Catalog count == unique qid count across the sample.
        Set<String> uniqueQids = new Set<String>{
            'qid-700-a', 'qid-700-b', 'qid-A-shared',
            'qid-B-branch', 'qid-B-child'
        };
        System.assertEquals(uniqueQids.size(), ir.catalog_entries.size(),
            'Catalog dedupe by qid across the whole sample');
    }

    @isTest
    static void parse_optionsOverrideTemplateExternalRef() {
        NeuraFormSteritechAdapter a = new NeuraFormSteritechAdapter();
        String src = buildSampleSteritech();
        NeuraFormIR ir = a.parse(src, new Map<String, String>{
            'template_external_ref' => 'custom_ref',
            'template_name' => 'Custom Name'
        });
        System.assertEquals('custom_ref', ir.template.external_ref);
        System.assertEquals('Custom Name', ir.template.name);
    }

    // -----------------------------------------------------------------
    // Fixture builders
    // -----------------------------------------------------------------

    /**
     * A 4-line-item sample that exercises:
     *   - Two prefix buckets (700-series numeric, A-letter, B-letter)
     *   - A shared qid across two sections (catalog dedupe)
     *   - A nested branch question (recursive flatten)
     *   - A null-named placeholder is NOT included here to keep this
     *     fixture focused — the placeholder case is exercised by
     *     parse_handlesNullQuestionName above.
     */
    private static String buildSampleSteritech() {
        List<Object> items = new List<Object>{
            buildLineItem('700', 'Pest prevention info', 'Policy 700',
                new List<Object>{
                    buildLeafQuestion('qid-700-a', 'Enter the date of last service.'),
                    buildLeafQuestion('qid-700-b', 'Briefly describe pests observed.')
                }),
            buildLineItem('701', 'Health inspection', 'Policy 701',
                new List<Object>{
                    buildLeafQuestion('qid-700-a', 'Enter the date of last service.')
                }),
            buildLineItem('A101', 'Cold holding', 'Policy A101',
                new List<Object>{
                    buildLeafQuestion('qid-A-shared', 'Was cold holding compliant?')
                }),
            buildLineItem('B205', 'Time control', 'Policy B205',
                new List<Object>{
                    buildBranchQuestion('qid-B-branch', 'Is time control in use?',
                        new List<Map<String, Object>>{
                            option('Yes', buildLeafQuestion('qid-B-child', 'Enter the time noted on the label.')),
                            option('No', null)
                        })
                })
        };
        return JSON.serialize(items);
    }

    private static Map<String, Object> buildLineItem(
        String code, String title, String policy, List<Object> questions
    ) {
        return new Map<String, Object>{
            'line_item_code' => code,
            'line_item_title' => title,
            'policy' => policy,
            'questions' => questions
        };
    }

    private static Map<String, Object> buildLeafQuestion(String qid, String name) {
        return new Map<String, Object>{
            'question_id' => qid,
            'question_name' => name
        };
    }

    private static Map<String, Object> buildBranchQuestion(
        String qid, String name, List<Map<String, Object>> opts
    ) {
        List<Object> wrapped = new List<Object>();
        for (Map<String, Object> o : opts) wrapped.add(o);
        return new Map<String, Object>{
            'question_id' => qid,
            'question_name' => name,
            'options' => wrapped
        };
    }

    private static Map<String, Object> option(
        String name, Map<String, Object> child
    ) {
        Map<String, Object> o = new Map<String, Object>{
            'option_name' => name
        };
        if (child != null) o.put('child_question', child);
        return o;
    }
}
