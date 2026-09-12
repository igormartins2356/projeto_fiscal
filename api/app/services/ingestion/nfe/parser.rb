module Ingestion
  module Nfe
    # XML NF-e/NFC-e (layout 4.00, com ou sem grupos IBS/CBS/IS) → documento canônico (CANONICO.md).
    # Só mapeia; derivações ficam em Derivations. Decimais como string; campo ausente = chave ausente.
    class Parser
      NS = { "n" => "http://www.portalfiscal.inf.br/nfe" }
      PURPOSE = { "1" => "normal", "2" => "complementary", "3" => "adjustment", "4" => "return" }
      SCOPE = { "1" => "intrastate", "2" => "interstate", "3" => "foreign" }
      IE_IND = { "1" => "taxpayer", "2" => "exempt", "9" => "non_taxpayer" }
      ENVIRONMENT = { "1" => "production", "2" => "homologation" }
      EMISSION = { "1" => "normal", "2" => "contingency_fsda", "4" => "epec", "6" => "svc_an", "7" => "svc_rs", "9" => "offline_nfce" }
      PRESENCE = { "0" => "not_applicable", "1" => "in_person", "2" => "internet", "3" => "phone", "4" => "home_delivery", "5" => "in_person_off_premises", "9" => "other" }
      FREIGHT = { "0" => "issuer_cif", "1" => "recipient_fob", "2" => "third_party", "3" => "own_sender", "4" => "own_recipient", "9" => "no_freight" }
      TOTALS = { "icms_base" => "vBC", "icms" => "vICMS", "icms_exempted" => "vICMSDeson", "fcp" => "vFCP", "icms_st_base" => "vBCST",
                 "icms_st" => "vST", "fcp_st" => "vFCPST", "fcp_st_withheld" => "vFCPSTRet", "fcp_uf_dest_base" => "vBCFCPUFDest",
                 "fcp_uf_dest" => "vFCPUFDest", "icms_uf_dest" => "vICMSUFDest", "icms_uf_sender" => "vICMSUFRemet", "products" => "vProd",
                 "freight" => "vFrete", "insurance" => "vSeg", "discount" => "vDesc", "other_expenses" => "vOutro", "ii" => "vII",
                 "ipi" => "vIPI", "ipi_returned" => "vIPIDevol", "pis" => "vPIS", "cofins" => "vCOFINS", "total" => "vNF", "approx_taxes" => "vTotTrib" }

      class InvalidXml < StandardError; end

      def self.call(xml) = new(xml).call

      def initialize(xml)
        @raw = xml
        @xml = Nokogiri::XML(xml) { |c| c.noblanks }
        @xml.remove_namespaces!
      end

      def call
        return parse_event if @xml.at("//evento") || @xml.at("//procEventoNFe")
        return parse_invalidation if @xml.at("//inutNFe")
        inf = @xml.at("//infNFe") or raise InvalidXml, "infNFe not found"
        ide = inf.at("ide")
        model = t(ide, "mod")
        doc = {
          "schema_version" => 1,
          "kind" => model == "65" ? "nfce" : "nfe",
          "model" => model,
          "access_key" => inf["Id"].to_s.sub(/\ANFe/, ""),
          "layout_version" => inf["versao"],
          "xml_hash" => Digest::SHA256.hexdigest(@raw),
          "environment" => ENVIRONMENT[t(ide, "tpAmb")],
          "issuance" => compact(
            "issued_at" => t(ide, "dhEmi"), "dispatched_at" => t(ide, "dhSaiEnt"), "series" => t(ide, "serie"),
            "number" => int(t(ide, "nNF")), "numeric_code" => t(ide, "cNF"), "emission_type" => EMISSION[t(ide, "tpEmis")],
            "purpose" => PURPOSE[t(ide, "finNFe")], "app_version" => t(ide, "verProc")
          ),
          "operation" => compact(
            "nature_text" => t(ide, "natOp"), "direction_declared" => t(ide, "tpNF") == "0" ? "inbound" : "outbound",
            "scope" => SCOPE[t(ide, "idDest")], "taxable_event_city_code" => t(ide, "cMunFG"),
            "final_consumer" => bool(t(ide, "indFinal")), "presence" => PRESENCE[t(ide, "indPres")],
            "intermediary" => { "0" => "none", "1" => "third_party_platform" }[t(ide, "indIntermed")]
          ),
          "references" => ide.xpath("NFref").map { |r| reference(r) },
          "issuer" => party(inf.at("emit"), "enderEmit"),
          "recipient" => party(inf.at("dest"), "enderDest"),
          "totals" => totals(inf.at("total")),
          "transport" => transport(inf.at("transp")),
          "payments" => inf.xpath("pag/detPag").map { |p| payment(p) },
          "additional_info" => compact("tax_authority" => t(inf.at("infAdic"), "infAdFisco"), "complementary" => t(inf.at("infAdic"), "infCpl")),
          "protocol" => protocol,
          "items" => inf.xpath("det").map { |d| item(d) }
        }
        doc["ibs_cbs"] = compact("taxable_event_city_code" => t(ide, "cMunFGIBS"), "debit_note_type" => t(ide, "tpNFDebito"), "credit_note_type" => t(ide, "tpNFCredito"))
        doc.delete("ibs_cbs") if doc["ibs_cbs"].empty?
        rt = inf.at("infRespTec")
        doc["technical_responsible"] = compact("cnpj" => t(rt, "CNPJ"), "contact" => t(rt, "xContato"), "email" => t(rt, "email"), "phone" => t(rt, "fone")) if rt
        doc["layout_groups"] = layout_groups(doc)
        doc.compact
      end

      private

      def t(node, name) = node&.at(name)&.text&.strip.presence
      def int(v) = v && Integer(v, 10)
      def bool(v) = v.nil? ? nil : v == "1"
      def compact(h) = h.reject { |_, v| v.nil? || (v.respond_to?(:empty?) && v.empty?) }
      def dec(node, name) = t(node, name)

      def reference(r)
        if (k = t(r, "refNFe")) then { "kind" => "nfe", "access_key" => k }
        elsif (c = t(r, "refCTe")) then { "kind" => "cte", "access_key" => c }
        elsif (nf = r.at("refNF")) then { "kind" => "nf_model_1", "nf_model_1" => { "uf" => t(nf, "cUF"), "yymm" => t(nf, "AAMM"), "cnpj" => t(nf, "CNPJ"), "model" => t(nf, "mod"), "series" => t(nf, "serie"), "number" => int(t(nf, "nNF")) } }
        elsif (nfp = r.at("refNFP")) then { "kind" => "producer_nf", "nf_producer" => { "uf" => t(nfp, "cUF"), "cnpj" => t(nfp, "CNPJ"), "cpf" => t(nfp, "CPF"), "ie" => t(nfp, "IE"), "number" => int(t(nfp, "nNF")) } }
        elsif (e = r.at("refECF")) then { "kind" => "ecf", "ecf" => { "model" => t(e, "mod"), "ecf_number" => t(e, "nECF"), "coo" => t(e, "nCOO") } }
        else { "kind" => "unknown" }
        end.compact
      end

      def party(node, addr_name)
        return {} unless node
        addr = node.at(addr_name)
        crt = t(node, "CRT")
        compact(
          "cnpj" => t(node, "CNPJ"), "cpf" => t(node, "CPF"), "foreign_id" => t(node, "idEstrangeiro"),
          "legal_name" => t(node, "xNome"), "trade_name" => t(node, "xFant"), "ie" => t(node, "IE"), "ie_st" => t(node, "IEST"),
          "im" => t(node, "IM"), "isuf" => t(node, "ISUF"), "cnae" => t(node, "CNAE"), "crt" => crt, "email" => t(node, "email"),
          "ie_indicator" => IE_IND[t(node, "indIEDest")],
          "address" => addr && compact("street" => t(addr, "xLgr"), "number" => t(addr, "nro"), "complement" => t(addr, "xCpl"), "district" => t(addr, "xBairro"),
                                       "city_code" => t(addr, "cMun"), "city" => t(addr, "xMun"), "uf" => t(addr, "UF"), "zip_code" => t(addr, "CEP"),
                                       "country_code" => t(addr, "cPais"), "country" => t(addr, "xPais"), "phone" => t(addr, "fone")),
          "uf" => addr && t(addr, "UF")
        )
      end

      def totals(total)
        tot = total&.at("ICMSTot")
        h = TOTALS.transform_values { |x| dec(tot, x) }
        ibs = total&.at("IBSCBSTot")
        if ibs
          h["ibs_cbs"] = compact("base_amount" => dec(ibs, "vBCIBSCBS"), "ibs_uf" => dec(ibs.at("gIBS/gIBSUF"), "vIBSUF"), "ibs_city" => dec(ibs.at("gIBS/gIBSMun"), "vIBSMun"),
                                 "ibs" => dec(ibs.at("gIBS"), "vIBS"), "cbs" => dec(ibs.at("gCBS"), "vCBS"),
                                 "presumed_credit_ibs" => dec(ibs.at("gIBS"), "vCredPres"), "presumed_credit_cbs" => dec(ibs.at("gCBS"), "vCredPres"), "is" => dec(total.at("ISTot"), "vIS"))
        end
        ret = total&.at("retTrib")
        h["withholdings"] = compact("pis" => dec(ret, "vRetPIS"), "cofins" => dec(ret, "vRetCOFINS"), "csll" => dec(ret, "vRetCSLL"), "irrf_base" => dec(ret, "vBCIRRF"), "irrf" => dec(ret, "vIRRF"), "social_security_base" => dec(ret, "vBCRetPrev"), "social_security" => dec(ret, "vRetPrev")) if ret
        compact(h)
      end

      def transport(tr)
        return {} unless tr
        c = tr.at("transporta")
        compact("freight_mode" => FREIGHT[t(tr, "modFrete")],
                "carrier" => c && compact("cnpj" => t(c, "CNPJ"), "cpf" => t(c, "CPF"), "name" => t(c, "xNome"), "ie" => t(c, "IE"), "address" => t(c, "xEnder"), "city" => t(c, "xMun"), "uf" => t(c, "UF")),
                "volumes" => tr.xpath("vol").map { |v| compact("quantity" => int(t(v, "qVol")), "kind" => t(v, "esp"), "brand" => t(v, "marca"), "numbering" => t(v, "nVol"), "net_weight" => dec(v, "pesoL"), "gross_weight" => dec(v, "pesoB")) })
      end

      def payment(p)
        card = p.at("card")
        compact("timing" => { "0" => "cash", "1" => "installment" }[t(p, "indPag")], "method" => t(p, "tPag"), "method_description" => t(p, "xPag"), "amount" => dec(p, "vPag"),
                "card" => card && compact("integration_type" => t(card, "tpIntegra"), "acquirer_cnpj" => t(card, "CNPJ"), "brand" => t(card, "tBand"), "authorization" => t(card, "cAut")))
      end

      def protocol
        p = @xml.at("//protNFe/infProt") or return {}
        compact("number" => t(p, "nProt"), "received_at" => t(p, "dhRecbto"), "status_code" => t(p, "cStat"), "digest" => t(p, "digVal"))
      end

      def item(det)
        prod, imp = det.at("prod"), det.at("imposto")
        gtin = t(prod, "cEAN")
        product = compact(
          "code" => t(prod, "cProd"), "gtin" => (gtin unless gtin == "SEM GTIN"), "no_gtin" => (true if gtin == "SEM GTIN"), "taxable_gtin" => t(prod, "cEANTrib").then { |g| g unless g == "SEM GTIN" },
          "description" => t(prod, "xProd"), "ncm" => t(prod, "NCM"), "nve" => prod.xpath("NVE").map(&:text).presence, "cest" => t(prod, "CEST"),
          "scale_indicator" => { "S" => "relevant", "N" => "not_relevant" }[t(prod, "indEscala")], "manufacturer_cnpj" => t(prod, "CNPJFab"), "benefit_code" => t(prod, "cBenef"),
          "ex_tipi" => t(prod, "EXTIPI"), "cfop" => t(prod, "CFOP"), "commercial_unit" => t(prod, "uCom"), "commercial_quantity" => dec(prod, "qCom"), "commercial_unit_price" => dec(prod, "vUnCom"),
          "gross_amount" => dec(prod, "vProd"), "taxable_unit" => t(prod, "uTrib"), "taxable_quantity" => dec(prod, "qTrib"), "taxable_unit_price" => dec(prod, "vUnTrib"),
          "freight" => dec(prod, "vFrete"), "insurance" => dec(prod, "vSeg"), "discount" => dec(prod, "vDesc"), "other_expenses" => dec(prod, "vOutro"),
          "included_in_total" => bool(t(prod, "indTot")), "purchase_order" => t(prod, "xPed"), "purchase_order_item" => int(t(prod, "nItemPed")), "fci" => t(prod, "nFCI"),
          "used_movable_good" => bool(t(prod, "indBemMovelUsado"))
        )
        h = { "number" => int(det["nItem"]), "product" => product }
        h["additional_info"] = t(det, "infAdProd") if t(det, "infAdProd")
        h["approx_taxes"] = dec(imp, "vTotTrib") if dec(imp, "vTotTrib")
        icms(h, imp&.at("ICMS"))
        ufdest(h, imp&.at("ICMSUFDest"))
        ipi(h, imp&.at("IPI"))
        pis_cofins(h, "pis", imp&.at("PIS"), "PIS")
        pis_cofins(h, "cofins", imp&.at("COFINS"), "COFINS")
        h["issqn"] = { "present" => true } if imp&.at("ISSQN")
        ibs_cbs(h, det.at("imposto/IBSCBS") || det.at("IBSCBS"))
        is(h, det.at("imposto/IS") || det.at("IS"))
        h
      end

      def icms(h, icms)
        g = icms&.element_children&.first or return
        base = compact(
          "group" => g.name, "origin" => t(g, "orig"), "cst" => t(g, "CST"), "csosn" => t(g, "CSOSN"), "base_mode" => t(g, "modBC"),
          "base_reduction_pct" => dec(g, "pRedBC"), "base_amount" => dec(g, "vBC"), "rate" => dec(g, "pICMS"), "amount" => dec(g, "vICMS"),
          "fcp" => compact("base_amount" => dec(g, "vBCFCP"), "rate" => dec(g, "pFCP"), "amount" => dec(g, "vFCP")),
          "exemption" => compact("amount" => dec(g, "vICMSDeson"), "reason_code" => t(g, "motDesICMS"), "deducts" => bool(t(g, "indDeduzDeson"))),
          "deferral" => compact("pct" => dec(g, "pDif"), "operation_amount" => dec(g, "vICMSOp"), "deferred_amount" => dec(g, "vICMSDif")),
          "simples_credit" => compact("rate" => dec(g, "pCredSN"), "amount" => dec(g, "vCredICMSSN"))
        )
        h["icms"] = base
        st = compact(
          "base_mode" => t(g, "modBCST"), "mva_pct" => dec(g, "pMVAST"), "base_reduction_pct" => dec(g, "pRedBCST"), "base_amount" => dec(g, "vBCST"), "rate" => dec(g, "pICMSST"), "amount" => dec(g, "vICMSST"),
          "fcp" => compact("base_amount" => dec(g, "vBCFCPST"), "rate" => dec(g, "pFCPST"), "amount" => dec(g, "vFCPST")),
          "withheld" => compact("base_amount" => dec(g, "vBCSTRet"), "final_consumer_rate" => dec(g, "pST"), "amount" => dec(g, "vICMSSTRet"), "substitute_amount" => dec(g, "vICMSSubstituto"),
                                "fcp" => compact("base_amount" => dec(g, "vBCFCPSTRet"), "rate" => dec(g, "pFCPSTRet"), "amount" => dec(g, "vFCPSTRet"))),
          "exemption" => compact("amount" => dec(g, "vICMSSTDeson"), "reason_code" => t(g, "motDesICMSST"))
        )
        h["icms_st"] = st unless st.empty?
      end

      def ufdest(h, u)
        return unless u
        h["icms_uf_dest"] = compact("base_amount" => dec(u, "vBCUFDest"), "fcp" => compact("base_amount" => dec(u, "vBCFCPUFDest"), "rate" => dec(u, "pFCPUFDest"), "amount" => dec(u, "vFCPUFDest")),
                                    "destination_internal_rate" => dec(u, "pICMSUFDest"), "interstate_rate" => dec(u, "pICMSInter"), "sharing_pct" => dec(u, "pICMSInterPart"),
                                    "destination_amount" => dec(u, "vICMSUFDest"), "sender_amount" => dec(u, "vICMSUFRemet"))
      end

      def ipi(h, ipi)
        return unless ipi
        g = ipi.at("IPITrib") || ipi.at("IPINT")
        h["ipi"] = compact("producer_cnpj" => t(ipi, "CNPJProd"), "framing_code" => t(ipi, "cEnq"), "seal" => compact("code" => t(ipi, "cSelo"), "quantity" => int(t(ipi, "qSelo"))),
                           "cst" => t(g, "CST"), "taxed" => !ipi.at("IPITrib").nil?, "base_amount" => dec(g, "vBC"), "rate" => dec(g, "pIPI"), "amount" => dec(g, "vIPI"),
                           "quantity" => dec(g, "qUnid"), "unit_amount" => dec(g, "vUnid"))
      end

      def pis_cofins(h, key, node, prefix)
        return unless node
        g = node.element_children.first or return
        h[key] = compact("group" => g.name, "cst" => t(g, "CST"), "base_amount" => dec(g, "vBC"), "rate" => dec(g, "p#{prefix}"), "amount" => dec(g, "v#{prefix}"),
                         "base_quantity" => dec(g, "qBCProd"), "unit_rate" => dec(g, "vAliqProd"))
        st = node.parent.at("#{prefix}ST")
        h["#{key}_st"] = compact("base_amount" => dec(st, "vBC"), "rate" => dec(st, "p#{prefix}"), "amount" => dec(st, "v#{prefix}"), "base_quantity" => dec(st, "qBCProd"), "unit_rate" => dec(st, "vAliqProd"), "add_to_total" => bool(t(st, "indSoma#{prefix}ST"))) if st
      end

      def ibs_cbs(h, n)
        return unless n
        g = n.at("gIBSCBS")
        rate_group = ->(x) { x && compact("rate" => dec(x, x.name == "gCBS" ? "pCBS" : x.name == "gIBSUF" ? "pIBSUF" : "pIBSMun"), "deferral_pct" => dec(x, "pDif"), "deferral_amount" => dec(x, "vDif"),
                                          "refund_amount" => dec(x, "vDevTrib"), "reduction_pct" => dec(x, "pRedAliq"), "effective_rate" => dec(x, "pAliqEfet"),
                                          "amount" => dec(x, x.name == "gCBS" ? "vCBS" : x.name == "gIBSUF" ? "vIBSUF" : "vIBSMun")) }
        reg = g&.at("gTribRegular")
        h["ibs_cbs"] = compact(
          "present" => true, "cst" => t(n, "CST"), "class_code" => t(n, "cClassTrib"), "base_amount" => dec(g, "vBC"),
          "ibs_uf" => rate_group.(g&.at("gIBSUF")), "ibs_city" => rate_group.(g&.at("gIBSMun")), "cbs" => rate_group.(g&.at("gCBS")),
          "ibs" => compact("amount" => dec(g, "vIBS")),
          "regular_taxation" => reg && compact("cst" => t(reg, "CSTReg"), "class_code" => t(reg, "cClassTribReg"), "ibs_uf_rate" => dec(reg, "pAliqEfetRegIBSUF"), "ibs_city_rate" => dec(reg, "pAliqEfetRegIBSMun"), "cbs_rate" => dec(reg, "pAliqEfetRegCBS"),
                                       "ibs_uf_amount" => dec(reg, "vTribRegIBSUF"), "ibs_city_amount" => dec(reg, "vTribRegIBSMun"), "cbs_amount" => dec(reg, "vTribRegCBS")),
          "presumed_credit" => compact("ibs" => g&.at("gIBSCredPres")&.then { |c| compact("code" => t(c, "cCredPres"), "pct" => dec(c, "pCredPres"), "amount" => dec(c, "vCredPres")) },
                                       "cbs" => g&.at("gCBSCredPres")&.then { |c| compact("code" => t(c, "cCredPres"), "pct" => dec(c, "pCredPres"), "amount" => dec(c, "vCredPres")) }),
          "single_phase" => n.at("gIBSCBSMono") && { "present" => true }
        )
      end

      def is(h, n)
        return unless n
        h["is"] = compact("cst" => t(n, "CSTIS"), "class_code" => t(n, "cClassTribIS"), "base_amount" => dec(n, "vBCIS"), "rate" => dec(n, "pIS"), "specific_rate" => dec(n, "pISEspec"), "quantity" => dec(n, "qTrib"), "unit" => t(n, "uTrib"), "amount" => dec(n, "vIS"))
      end

      EVENT_KIND = { "110111" => "cancellation", "110112" => "cancellation_by_replacement", "110110" => "correction_letter", "110140" => "epec", "210210" => "awareness",
                     "210200" => "confirmation", "210220" => "unknown_operation", "210240" => "operation_not_performed", "110150" => "interested_party", "110130" => "delivery_receipt" }

      def parse_event
        e = @xml.at("//evento/infEvento") or raise InvalidXml, "infEvento not found"
        ret = @xml.at("//retEvento/infEvento")
        det = e.at("detEvento")
        { "schema_version" => 1, "kind" => "event", "access_key" => t(e, "chNFe"), "xml_hash" => Digest::SHA256.hexdigest(@raw),
          "environment" => ENVIRONMENT[t(e, "tpAmb")],
          "event" => compact("code" => t(e, "tpEvento"), "kind" => EVENT_KIND[t(e, "tpEvento")], "sequence" => int(t(e, "nSeqEvento")), "occurred_at" => t(e, "dhEvento"),
                             "author" => t(e, "CNPJ") || t(e, "CPF"), "justification" => t(det, "xJust"), "correction_text" => t(det, "xCorrecao"),
                             "referenced_protocol" => t(det, "nProt"), "replacement_access_key" => t(det, "chNFeRef")),
          "protocol" => ret ? compact("number" => t(ret, "nProt"), "received_at" => t(ret, "dhRegEvento"), "status_code" => t(ret, "cStat")) : {} }.compact
      end

      def parse_invalidation
        i = @xml.at("//inutNFe/infInut") or raise InvalidXml, "infInut not found"
        ret = @xml.at("//retInutNFe/infInut")
        { "schema_version" => 1, "kind" => "invalidation", "xml_hash" => Digest::SHA256.hexdigest(@raw),
          "environment" => ENVIRONMENT[t(i, "tpAmb")],
          "invalidation" => compact("cnpj" => t(i, "CNPJ"), "uf_code" => t(i, "cUF"), "year" => t(i, "ano"), "model" => t(i, "mod"), "series" => t(i, "serie"),
                                    "first_number" => int(t(i, "nNFIni")), "last_number" => int(t(i, "nNFFin")), "justification" => t(i, "xJust")),
          "protocol" => ret ? compact("number" => t(ret, "nProt"), "received_at" => t(ret, "dhRecbto"), "status_code" => t(ret, "cStat")) : {} }.compact
      end

      def layout_groups(doc)
        g = []
        g << "ibs_cbs" if doc["items"].any? { |i| i["ibs_cbs"] }
        g << "is" if doc["items"].any? { |i| i["is"] }
        g << "icms_uf_dest" if doc["items"].any? { |i| i["icms_uf_dest"] }
        g << "payment" if doc["payments"].any?
        g
      end
    end
  end
end
