"""Delete explicitly named AWS external-function lab resources; preview by default."""
import argparse
import json
import os
import sys
import boto3
from dotenv import load_dotenv


def items(client, operation, key, **kwargs):
    return [item for page in client.get_paginator(operation).paginate(**kwargs) for item in page.get(key, [])]


def optional(call, **kwargs):
    try:
        return call(**kwargs)
    except Exception as exc:
        code = getattr(exc, 'response', {}).get('Error', {}).get('Code')

        if code in {'NotFoundException', 'ResourceNotFoundException', 'NoSuchEntity'}:
            return None

        raise


def matches_invocation_policy(policy, resource):
    """Allow only the lab's root and optional FX invocation permissions."""
    statements = policy.get('Statement', [])

    if isinstance(statements, dict):
        statements = [statements]

    if not statements:
        return False

    allowed_resources = set()
    for statement in statements:
        actions = statement.get('Action', [])
        resources = statement.get('Resource', [])

        if isinstance(actions, str):
            actions = [actions]

        if isinstance(resources, str):
            resources = [resources]
            
        if (statement.get('Effect') != 'Allow'
                or actions != ['execute-api:Invoke']
                or not resources
                or any(r not in {resource, resource + 'fx'} for r in resources)
                or set(statement) - {'Sid', 'Effect', 'Action', 'Resource'}):
            return False

        allowed_resources.update(resources)

    return resource in allowed_resources


def build_plan(session, args):
    account = session.client('sts').get_caller_identity()['Account']

    if account != args.account_id:
        raise ValueError(f'Wrong AWS account: authenticated as {account}, expected {args.account_id}')

    gateway = session.client('apigateway', region_name=args.region)
    lam = session.client('lambda', region_name=args.region)
    logs = session.client('logs', region_name=args.region)
    iam = session.client('iam')
    plan = []

    api = optional(gateway.get_rest_api, restApiId=args.api_id)

    if api:
        if api['name'] != args.api_name:
            raise ValueError('API ID exists but its name does not match AWS_API_NAME.')

        plan.append((gateway, 'delete_rest_api', {'restApiId': args.api_id}))

    fn = optional(lam.get_function, FunctionName=args.function)

    if fn:
        if fn['Configuration']['FunctionArn'].split(':')[4] != account:
            raise ValueError('Lambda account mismatch.')

        plan.append((lam, 'delete_function', {'FunctionName': args.function}))

    group = '/aws/lambda/' + args.function
    if any(g['logGroupName'] == group for g in items(
            logs, 'describe_log_groups', 'logGroups', logGroupNamePrefix=group)):
        plan.append((logs, 'delete_log_group', {'logGroupName': group}))

    roles = [(args.invoke_role, False)]

    if args.lambda_role:
        if args.lambda_role == args.invoke_role:
            raise ValueError('Lambda execution role and invocation role must be different.')

        roles.append((args.lambda_role, True))

    for name, is_execution in roles:
        role_result = optional(iam.get_role, RoleName=name)

        if not role_result:
            continue

        role = role_result['Role']

        if role['Arn'].split(':')[4] != account:
            raise ValueError('IAM account mismatch.')

        if items(iam, 'list_instance_profiles_for_role', 'InstanceProfiles', RoleName=name):
            raise ValueError(f'Role {name} has instance profiles; refusing deletion.')

        if is_execution:
            if fn and fn['Configuration']['Role'] != role['Arn']:
                raise ValueError('AWS_LAMBDA_EXECUTION_ROLE does not match the function execution role.')

            # Refuse service roles with broader trust than the dedicated Lambda role.
            statements = role['AssumeRolePolicyDocument']['Statement']

            if isinstance(statements, dict):
                statements = [statements]
            allowed = [s for s in statements if s.get('Effect') == 'Allow']

            if not allowed or any(s.get('Principal') != {'Service': 'lambda.amazonaws.com'} for s in allowed):
                raise ValueError(f'Role {name} is not exclusively trusted by Lambda.')

        # IAM roles are global: check all enabled regions, including published versions.
        regions = session.client('ec2', region_name=args.region).describe_regions()['Regions']

        for region in regions:
            client = session.client('lambda', region_name=region['RegionName'])

            for other in items(client, 'list_functions', 'Functions', FunctionVersion='ALL'):
                if other.get('Role') == role['Arn']:
                    is_target = (
                        is_execution
                        and region['RegionName'] == args.region
                        and other['FunctionName'] == args.function
                    )

                    if not is_target:
                        raise ValueError(f'Role {name} is used by Lambda {other["FunctionName"]} '
                                         f'in {region["RegionName"]}; refusing deletion.')
        inline = items(iam, 'list_role_policies', 'PolicyNames', RoleName=name)
        attached = items(iam, 'list_attached_role_policies', 'AttachedPolicies', RoleName=name)

        if not is_execution:
            if attached or any(p != args.invoke_policy for p in inline):
                raise ValueError(f'Invocation role {name} has unexpected policies; review manually.')

            if args.invoke_policy in inline:
                policy = iam.get_role_policy(RoleName=name, PolicyName=args.invoke_policy)['PolicyDocument']
                expected = f'arn:aws:execute-api:{args.region}:{account}:{args.api_id}/demo/POST/'

                if not matches_invocation_policy(policy, expected):
                    print('Allowed invocation resources:', expected, 'and', expected + 'fx')
                    print('Actual invocation policy:', json.dumps(policy, indent=2))
                    raise ValueError('Invocation policy differs from this lab endpoint; review manually.')

        for policy in inline:
            plan.append((iam, 'delete_role_policy', {'RoleName': name, 'PolicyName': policy}))

        for policy in attached:
            plan.append((iam, 'detach_role_policy', {'RoleName': name, 'PolicyArn': policy['PolicyArn']}))

        plan.append((iam, 'delete_role', {'RoleName': name}))

    return plan


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--execute', action='store_true', help='Delete the displayed resources')
    args = parser.parse_args(argv)

    # Resolve from the script location, independent of the working directory.
    # Existing environment variables take precedence; never print credentials.
    load_dotenv()
    args.account_id = os.getenv('AWS_ACCOUNT_ID', '').strip()
    args.region = os.getenv('AWS_DEFAULT_REGION', 'us-east-2').strip()
    args.api_id = os.getenv('AWS_API_ID', '').strip()
    args.api_name = os.getenv('AWS_API_NAME', 'snowflake-order-risk-api').strip()
    args.function = os.getenv('AWS_LAMBDA_FUNCTION', 'snowflake-order-risk-demo').strip()
    args.invoke_role = os.getenv('AWS_INVOKE_ROLE', 'SnowflakeOrderRiskInvokeRole').strip()
    args.invoke_policy = os.getenv('AWS_INVOKE_POLICY', 'InvokeOrderRiskDemo').strip()
    # Captured after notebook Step 3 and included in its generated .env output.
    args.lambda_role = os.getenv('AWS_LAMBDA_EXECUTION_ROLE', '').strip() or None

    try:
        if args.lambda_role and (args.lambda_role.startswith('arn:') or
                                 args.lambda_role == 'PASTE_LAMBDA_EXECUTION_ROLE_NAME_HERE'):
            raise ValueError('Set AWS_LAMBDA_EXECUTION_ROLE to the role NAME copied from '
                             'Lambda > Configuration > Permissions, not an ARN or placeholder.')

        if not args.account_id or not args.api_id:
            raise ValueError('Set AWS_ACCOUNT_ID and AWS_API_ID in the repository .env file.')

        session_options = {'region_name': args.region}
        access_key = os.getenv('AWS_ACCESS_KEY_ID')
        secret_key = os.getenv('AWS_SECRET_ACCESS_KEY')

        if not access_key or not secret_key:
            raise ValueError('Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY in the repository .env file.')

        session_options.update(
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            aws_session_token=os.getenv('AWS_SESSION_TOKEN') or None,
        )
        session = boto3.Session(**session_options)

        # Complete read-only preflight before any deletion. AccessDenied is never treated as absent.
        plan = build_plan(session, args)

        print(f'Account: {args.account_id}; region: {args.region}')
        print('EXECUTE' if args.execute else 'PREVIEW ONLY - no changes')

        for _, operation, params in plan:
            print(operation, json.dumps(params))

        if not args.lambda_role:
            print('Lambda execution role retained: set AWS_LAMBDA_EXECUTION_ROLE in .env to its exact name to include it.')

        print('Managed policy objects are retained; attachments on deleted roles are removed.')

        if args.execute:
            for client, operation, params in plan:
                optional(getattr(client, operation), **params)
                print('Completed:', operation, json.dumps(params))

        if not plan:
            print('No matching resources remain.')
        elif not args.execute:
            print('Review the plan, then rerun with --execute to delete.')

        return 0

    except Exception as exc:
        print(f'Stopped: {exc}', file=sys.stderr)
        print('Resolve the error and rerun; already absent resources are skipped.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
