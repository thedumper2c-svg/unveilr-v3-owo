type AstExpression = {
    kind: string,
    data: {
        [any]: any
    }
}

local Ast = {}

local concat = table.concat
local insert = table.insert
local format = string.format

function Ast.Assign(Variables: {string}, Values: {AstExpression}, IsGlobal: boolean): AstExpression
    return {
        kind = "assign",
        data = {
            vars = Variables,
            values = Values,
            type = IsGlobal and "global" or "local"
        }
    }
end

function Ast.Number(Value: number): AstExpression
    return {
        kind = "number",
        data = {
            value = Value
        }
    }
end

function Ast.String(Value: string): AstExpression
    return {
        kind = "string",
        data = {
            value = Value
        }
    }
end

function Ast.Boolean(Value: boolean): AstExpression
    return {
        kind = "boolean",
        data = {
            value = Value
        }
    }
end

function Ast.BinaryOp(Left: AstExpression, Operator: string, Right: AstExpression): AstExpression
    return {
        kind = "binaryop",
        data = {
            left = Left,
            operator = Operator,
            right = Right
        }
    }
end

function Ast.Variable(Name: string): AstExpression
    return {
        kind = "variable",
        data = {
            name = Name
        }
    }
end

function Ast.FunctionCall(FunctionName: string, Arguments: {AstExpression}): AstExpression
    return {
        kind = "call",
        data = {
            func = FunctionName,
            args = Arguments
        }
    }
end

function Ast.Function(Name: string?, Parameters: {string}, Body: AstExpression, IsLocal: boolean?): AstExpression
    return {
        kind = "function",
        data = {
            name = Name,
            params = Parameters,
            body = Body,
            isLocal = IsLocal or false
        }
    }
end

function Ast.Return(Values: {AstExpression}): AstExpression
    return {
        kind = "return",
        data = {
            values = Values
        }
    }
end

function Ast.IfStat(Condition: AstExpression, ThenBlock: AstExpression, ElseBlock: AstExpression?): AstExpression
    return {
        kind = "if",
        data = {
            condition = Condition,
            thenBlock = ThenBlock,
            elseBlock = ElseBlock
        }
    }
end

function Ast.WhileLoop(Condition: AstExpression, Body: AstExpression): AstExpression
    return {
        kind = "while",
        data = {
            condition = Condition,
            body = Body
        }
    }
end

function Ast.Break() : AstExpression
    return {
        kind = "break",
        data = {}
    }
end

function Ast.Continue() : AstExpression
    return {
        kind = "continue",
        data = {}
    }
end

function Ast.ForNum(Variable: string, Start: AstExpression, End: AstExpression, Step: AstExpression?, Body: AstExpression): AstExpression
    return {
        kind = "fornum",
        data = {
            var = Variable,
            start = Start,
            ["end"] = End,
            step = Step,
            body = Body
        }
    }
end

function Ast.ForIn(Variables: {string}, Iterator: AstExpression, Body: AstExpression): AstExpression --> for i, v in 
    return {
        kind = "forin",
        data = {
            vars = Variables,
            iterator = Iterator,
            body = Body
        }
    }
end

function Ast.Block(Body : { AstExpression }) : AstExpression
    return {
        kind = "block",
        data = {
            statements = Body
        }
    }
end

function Ast.new(): AstExpression
    return {
        kind = "block",
        data = {
            statements = {}
        }
    }
end

function Ast.addStatement(self: AstExpression, statement: AstExpression)
    table.insert(self.data.statements, statement)
end

local function ExpressionToCode(expr: AstExpression, indent: number?): string
    local indentLevel = indent or 0
    local _indentStr = string.rep("    ", indentLevel)

    local Kind : string = expr.kind
    
    if Kind == "number" then
        return tostring(expr.data.value)
    elseif Kind == "string" then
        return '"' .. expr.data.value .. '"'
    elseif Kind == "boolean" then
        return tostring(expr.data.value)
    elseif Kind == "variable" then
        return expr.data.name
    elseif Kind == "binaryop" then
        return ExpressionToCode(expr.data.left, indentLevel) .. " " .. expr.data.operator .. " " .. ExpressionToCode(expr.data.right, indentLevel)
    elseif Kind == "call" then
        local args = {}
        for _, arg in ipairs(expr.data.args) do
            table.insert(args, ExpressionToCode(arg, indentLevel))
        end
        return expr.data.func .. "(" .. table.concat(args, ", ") .. ")"
    end

    return ""
end

function AstToCode(AST: AstExpression, indent: number?): string
    local indentLevel : number = indent or 0
    local indentStr : string = string.rep("    ", indentLevel)
    local Code = {}

    if AST.kind == "block" then
        for _, Statement in ipairs(AST.data.statements) do
            local Current : string = indentStr

            local Kind : string = Statement.kind
            if Kind == "assign" then
                local Start = Statement.data.type == "local" and "local " or ""
                Start ..= concat(Statement.data.vars, ", ")

                if #Statement.data.values == 0 then
                    Start ..= ";"
                else
                    local values = {}
                    for _, value in ipairs(Statement.data.values) do
                        insert(values, ExpressionToCode(value, indentLevel))
                    end

                    Start ..= " = " .. concat(values, ", ")
                end
                Current ..= Start
            elseif Kind == "call" then
                Current ..= ExpressionToCode(Statement, indentLevel)
            elseif Kind == "function" then
                local localStr = Statement.data.isLocal and "local " or ""
                local nameStr = Statement.data.name and ("function " .. Statement.data.name) or "function"
                local params = concat(Statement.data.params, ", ")

                Current ..= format(
                    "%s%s(%s)\n%s\n%send",
                    localStr,
                    nameStr,
                    params,
                    AstToCode(Statement.data.body, indentLevel + 1),
                    indentStr
                )
                
            elseif Kind == "return" then
                local values = {}
                for _, value in ipairs(Statement.data.values) do
                    table.insert(values, ExpressionToCode(value, indentLevel))
                end
                Current ..= "return " .. table.concat(values, ", ")
                
            elseif Kind == "if" then
                Current ..= format(
                    "if %s then\n%s\n",
                    ExpressionToCode(Statement.data.condition, indentLevel),
                    AstToCode(Statement.data.thenBlock, indentLevel + 1)
                )

                if Statement.data.elseBlock then
                    Current ..= format(
                        "else\n%s",
                        AstToCode(Statement.data.elseBlock, indentLevel + 1)
                    )
                end

                Current ..= indentStr .. "end\n"
                
            elseif Kind == "while" then
                Current ..= format(
                    "while %s do\n%s\n%send",
                    ExpressionToCode(Statement.data.condition, indentLevel),
                    AstToCode(Statement.data.body, indentLevel + 1),
                    indentStr
                )
                
            elseif Kind == "fornum" then
                local step = Statement.data.step and (", " .. ExpressionToCode(Statement.data.step, indentLevel)) or ""
                Current ..= format(
                    "for %s = %s, %s, %s do\n%s\n%send",
                    Statement.data.var,
                    ExpressionToCode(Statement.data.start, indentLevel),
                    ExpressionToCode(Statement.data["end"], indentLevel),
                    step,
                    AstToCode(Statement.data.body, indentLevel + 1),
                    indentStr
                )
                
            elseif Kind == "forin" then
                Current ..= format(
                    "for %s in %s do\n%s\n%send",
                    concat(Statement.data.vars, ", "),
                    ExpressionToCode(Statement.data.iterator, indentLevel),
                    AstToCode(Statement.data.body, indentLevel + 1),
                    indentStr
                )
            elseif Kind == "break" then
                Current ..= "break"
            elseif Kind == "continue" then
                Current ..= "continue"
            end

            insert(Code, Current)
        end
    end
    
    return concat(Code, "\n")
end

return {
    Stringify = AstToCode,
    Ast = Ast
}